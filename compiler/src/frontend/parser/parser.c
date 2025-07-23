#include "parser.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

void parser_init(Parser* parser, Lexer* lexer, ASTArena* arena) {
    parser->lexer = lexer;
    parser->arena = arena;
    parser->had_error = false;
    parser->panic_mode = false;
    parser->error.type = PARSE_ERROR_NONE;
    parser->error.message = NULL;
    
    // Prime the parser with the first token
    parser->current = lexer_next_token(parser->lexer);
}

void parser_cleanup(Parser* parser) {
    if (parser->error.message) {
        free(parser->error.message);
        parser->error.message = NULL;
    }
}

static void advance(Parser* parser) {
    parser->previous = parser->current;
    
    for (;;) {
        parser->current = lexer_next_token(parser->lexer);
        if (parser->current.type != TOKEN_ERROR) break;
        
        parse_error_at_current(parser, parser->current.start);
    }
}

static bool check(Parser* parser, TokenType type) {
    return parser->current.type == type;
}

static bool match(Parser* parser, TokenType type) {
    if (!check(parser, type)) return false;
    advance(parser);
    return true;
}

static Token consume(Parser* parser, TokenType type, const char* message) {
    if (parser->current.type == type) {
        Token token = parser->current;
        advance(parser);
        return token;
    }
    
    parse_error_at_current(parser, message);
    return parser->current;
}

static bool is_at_end(Parser* parser) {
    return parser->current.type == TOKEN_EOF;
}

void parse_error(Parser* parser, const char* message) {
    parse_error_at(parser, parser->previous, message);
}

void parse_error_at(Parser* parser, Token token, const char* message) {
    if (parser->panic_mode) return;
    
    parser->panic_mode = true;
    parser->had_error = true;
    
    parser->error.type = PARSE_ERROR_UNEXPECTED_TOKEN;
    parser->error.token = token;
    parser->error.line = token.line;
    parser->error.column = token.column;
    
    if (parser->error.message) {
        free(parser->error.message);
    }
    parser->error.message = malloc(strlen(message) + 1);
    if (parser->error.message) {
        strcpy(parser->error.message, message);
    }
    
    fprintf(stderr, "[line %d:%d] Error", token.line, token.column);
    
    if (token.type == TOKEN_EOF) {
        fprintf(stderr, " at end");
    } else if (token.type == TOKEN_ERROR) {
        // Nothing
    } else {
        fprintf(stderr, " at '%.*s'", token.length, token.start);
    }
    
    fprintf(stderr, ": %s\n", message);
}

void parse_error_at_current(Parser* parser, const char* message) {
    parse_error_at(parser, parser->current, message);
}

void synchronize(Parser* parser) {
    parser->panic_mode = false;
    
    while (parser->current.type != TOKEN_EOF) {
        if (parser->previous.type == TOKEN_SEMICOLON) return;
        
        switch (parser->current.type) {
            case TOKEN_FUNC:
            case TOKEN_LET:
            case TOKEN_CONST:
            case TOKEN_FOR:
            case TOKEN_IF:
            case TOKEN_WHILE:
            case TOKEN_RETURN:
                return;
            default:
                break;
        }
        
        advance(parser);
    }
}

// Simple recursive descent parser
static ASTNode* parse_primary(Parser* parser) {
    if (match(parser, TOKEN_TRUE)) {
        return ast_create_literal_boolean(parser->arena, true, parser->previous);
    }
    
    if (match(parser, TOKEN_FALSE)) {
        return ast_create_literal_boolean(parser->arena, false, parser->previous);
    }
    
    if (match(parser, TOKEN_NULL)) {
        return ast_create_literal_null(parser->arena, parser->previous);
    }
    
    if (match(parser, TOKEN_NUMBER)) {
        Token token = parser->previous;
        char* number_str = malloc(token.length + 1);
        if (!number_str) return NULL;
        
        memcpy(number_str, token.start, token.length);
        number_str[token.length] = '\0';
        
        double value = strtod(number_str, NULL);
        free(number_str);
        
        return ast_create_literal_number(parser->arena, value, token);
    }
    
    if (match(parser, TOKEN_STRING)) {
        Token token = parser->previous;
        int content_length = token.length - 2; // Remove quotes
        char* content = malloc(content_length + 1);
        if (!content) return NULL;
        
        memcpy(content, token.start + 1, content_length);
        content[content_length] = '\0';
        
        ASTNode* result = ast_create_literal_string(parser->arena, content, token);
        free(content);
        return result;
    }
    
    if (match(parser, TOKEN_IDENTIFIER)) {
        Token token = parser->previous;
        char* name = malloc(token.length + 1);
        if (!name) return NULL;
        
        memcpy(name, token.start, token.length);
        name[token.length] = '\0';
        
        ASTNode* result = ast_create_identifier(parser->arena, name, token);
        free(name);
        return result;
    }
    
    if (match(parser, TOKEN_LEFT_PAREN)) {
        ASTNode* expr = parse_expression(parser);
        consume(parser, TOKEN_RIGHT_PAREN, "Expected ')' after expression");
        return expr;
    }
    
    parse_error_at_current(parser, "Expected expression");
    return NULL;
}

static ASTNode* parse_call(Parser* parser, ASTNode* callee) {
    Token call_token = parser->previous;
    
    ASTNode** arguments = NULL;
    int argument_count = 0;
    int argument_capacity = 0;
    
    if (!check(parser, TOKEN_RIGHT_PAREN)) {
        do {
            if (argument_count >= argument_capacity) {
                argument_capacity = argument_capacity == 0 ? 4 : argument_capacity * 2;
                arguments = realloc(arguments, sizeof(ASTNode*) * argument_capacity);
                if (!arguments) {
                    parse_error(parser, "Out of memory");
                    return NULL;
                }
            }
            
            arguments[argument_count] = parse_expression(parser);
            if (!arguments[argument_count]) {
                free(arguments);
                return NULL;
            }
            argument_count++;
        } while (match(parser, TOKEN_COMMA));
    }
    
    consume(parser, TOKEN_RIGHT_PAREN, "Expected ')' after arguments");
    
    return ast_create_call_expr(parser->arena, callee, arguments, argument_count, call_token);
}

static ASTNode* parse_postfix(Parser* parser) {
    ASTNode* expr = parse_primary(parser);
    
    while (true) {
        if (match(parser, TOKEN_LEFT_PAREN)) {
            expr = parse_call(parser, expr);
        } else {
            break;
        }
    }
    
    return expr;
}

static ASTNode* parse_unary(Parser* parser) {
    if (match(parser, TOKEN_NOT) || match(parser, TOKEN_MINUS)) {
        Token operator_token = parser->previous;
        ASTNode* right = parse_unary(parser);
        UnaryOperator op = (operator_token.type == TOKEN_NOT) ? UNARY_NOT : UNARY_MINUS;
        return ast_create_unary_expr(parser->arena, op, right, operator_token);
    }
    
    return parse_postfix(parser);
}

static ASTNode* parse_factor(Parser* parser) {
    ASTNode* expr = parse_unary(parser);
    
    while (match(parser, TOKEN_MULTIPLY) || match(parser, TOKEN_DIVIDE) || match(parser, TOKEN_MODULO)) {
        Token operator_token = parser->previous;
        ASTNode* right = parse_unary(parser);
        
        BinaryOperator op;
        switch (operator_token.type) {
            case TOKEN_MULTIPLY: op = BINARY_MULTIPLY; break;
            case TOKEN_DIVIDE: op = BINARY_DIVIDE; break;
            case TOKEN_MODULO: op = BINARY_MODULO; break;
            default: op = BINARY_MULTIPLY; break;
        }
        
        expr = ast_create_binary_expr(parser->arena, op, expr, right, operator_token);
    }
    
    return expr;
}

static ASTNode* parse_term(Parser* parser) {
    ASTNode* expr = parse_factor(parser);
    
    while (match(parser, TOKEN_PLUS) || match(parser, TOKEN_MINUS)) {
        Token operator_token = parser->previous;
        ASTNode* right = parse_factor(parser);
        
        BinaryOperator op = (operator_token.type == TOKEN_PLUS) ? BINARY_ADD : BINARY_SUBTRACT;
        expr = ast_create_binary_expr(parser->arena, op, expr, right, operator_token);
    }
    
    return expr;
}

static ASTNode* parse_comparison(Parser* parser) {
    ASTNode* expr = parse_term(parser);
    
    while (match(parser, TOKEN_GREATER) || match(parser, TOKEN_GREATER_EQUAL) ||
           match(parser, TOKEN_LESS) || match(parser, TOKEN_LESS_EQUAL)) {
        Token operator_token = parser->previous;
        ASTNode* right = parse_term(parser);
        
        BinaryOperator op;
        switch (operator_token.type) {
            case TOKEN_GREATER: op = BINARY_GREATER; break;
            case TOKEN_GREATER_EQUAL: op = BINARY_GREATER_EQUAL; break;
            case TOKEN_LESS: op = BINARY_LESS; break;
            case TOKEN_LESS_EQUAL: op = BINARY_LESS_EQUAL; break;
            default: op = BINARY_GREATER; break;
        }
        
        expr = ast_create_binary_expr(parser->arena, op, expr, right, operator_token);
    }
    
    return expr;
}

static ASTNode* parse_equality(Parser* parser) {
    ASTNode* expr = parse_comparison(parser);
    
    while (match(parser, TOKEN_NOT_EQUAL) || match(parser, TOKEN_EQUAL) || match(parser, TOKEN_IS)) {
        Token operator_token = parser->previous;
        ASTNode* right = parse_comparison(parser);
        
        BinaryOperator op;
        switch (operator_token.type) {
            case TOKEN_NOT_EQUAL: op = BINARY_NOT_EQUAL; break;
            case TOKEN_EQUAL: op = BINARY_EQUAL; break;
            case TOKEN_IS: op = BINARY_IS; break;
            default: op = BINARY_EQUAL; break;
        }
        
        expr = ast_create_binary_expr(parser->arena, op, expr, right, operator_token);
    }
    
    return expr;
}

static ASTNode* parse_logic_and(Parser* parser) {
    ASTNode* expr = parse_equality(parser);
    
    while (match(parser, TOKEN_AND)) {
        Token operator_token = parser->previous;
        ASTNode* right = parse_equality(parser);
        expr = ast_create_binary_expr(parser->arena, BINARY_AND, expr, right, operator_token);
    }
    
    return expr;
}

static ASTNode* parse_logic_or(Parser* parser) {
    ASTNode* expr = parse_logic_and(parser);
    
    while (match(parser, TOKEN_OR)) {
        Token operator_token = parser->previous;
        ASTNode* right = parse_logic_and(parser);
        expr = ast_create_binary_expr(parser->arena, BINARY_OR, expr, right, operator_token);
    }
    
    return expr;
}

ASTNode* parse_expression(Parser* parser) {
    return parse_logic_or(parser);
}

static ZenType parse_type(Parser* parser) {
    switch (parser->current.type) {
        case TOKEN_I32:
            advance(parser);
            return TYPE_I32;
        case TOKEN_F64:
            advance(parser);
            return TYPE_F64;
        case TOKEN_STRING_TYPE:
            advance(parser);
            return TYPE_STRING;
        case TOKEN_BOOL:
            advance(parser);
            return TYPE_BOOL;
        case TOKEN_VOID:
            advance(parser);
            return TYPE_VOID;
        default:
            parse_error_at_current(parser, "Expected type");
            return TYPE_UNKNOWN;
    }
}

static ASTNode* parse_var_declaration(Parser* parser) {
    bool is_const = parser->previous.type == TOKEN_CONST;
    
    Token name_token = consume(parser, TOKEN_IDENTIFIER, "Expected variable name");
    
    char* name = malloc(name_token.length + 1);
    if (!name) {
        parse_error(parser, "Out of memory");
        return NULL;
    }
    memcpy(name, name_token.start, name_token.length);
    name[name_token.length] = '\0';
    
    ZenType var_type = TYPE_UNKNOWN;
    if (match(parser, TOKEN_COLON)) {
        var_type = parse_type(parser);
    }
    
    ASTNode* initializer = NULL;
    if (match(parser, TOKEN_ASSIGN)) {
        initializer = parse_expression(parser);
        if (!initializer) {
            free(name);
            return NULL;
        }
    }
    
    consume(parser, TOKEN_SEMICOLON, "Expected ';' after variable declaration");
    
    ASTNode* result = ast_create_var_declaration(parser->arena, name, var_type, is_const, initializer, parser->previous);
    free(name);
    return result;
}

static ASTNode* parse_expression_statement(Parser* parser) {
    ASTNode* expr = parse_expression(parser);
    if (!expr) return NULL;
    
    // Skip optional semicolon and newlines
    while (match(parser, TOKEN_SEMICOLON) || match(parser, TOKEN_NEWLINE)) {
        // Continue
    }
    
    return ast_create_expression_stmt(parser->arena, expr, parser->previous);
}

static ASTNode* parse_block_statement(Parser* parser) {
    ASTNode** statements = NULL;
    int statement_count = 0;
    int statement_capacity = 0;
    
    while (!check(parser, TOKEN_RIGHT_BRACE) && !is_at_end(parser)) {
        // Skip newlines
        if (match(parser, TOKEN_NEWLINE)) {
            continue;
        }
        
        if (statement_count >= statement_capacity) {
            statement_capacity = statement_capacity == 0 ? 4 : statement_capacity * 2;
            statements = realloc(statements, sizeof(ASTNode*) * statement_capacity);
            if (!statements) {
                parse_error(parser, "Out of memory");
                return NULL;
            }
        }
        
        ASTNode* stmt = parse_statement(parser);
        if (stmt) {
            statements[statement_count++] = stmt;
        }
    }
    
    consume(parser, TOKEN_RIGHT_BRACE, "Expected '}' after block");
    
    return ast_create_block_stmt(parser->arena, statements, statement_count, parser->previous);
}

static ASTNode* parse_return_statement(Parser* parser) {
    ASTNode* value = NULL;
    if (!check(parser, TOKEN_SEMICOLON) && !check(parser, TOKEN_NEWLINE)) {
        value = parse_expression(parser);
        if (!value) return NULL;
    }
    
    // Skip optional semicolon
    if (match(parser, TOKEN_SEMICOLON) || match(parser, TOKEN_NEWLINE)) {
        // Continue
    }
    
    return ast_create_return_stmt(parser->arena, value, parser->previous);
}

static ASTNode* parse_function_declaration(Parser* parser) {
    Token name_token = consume(parser, TOKEN_IDENTIFIER, "Expected function name");
    
    char* name = malloc(name_token.length + 1);
    if (!name) {
        parse_error(parser, "Out of memory");
        return NULL;
    }
    memcpy(name, name_token.start, name_token.length);
    name[name_token.length] = '\0';
    
    consume(parser, TOKEN_LEFT_PAREN, "Expected '(' after function name");
    
    // Parse parameters
    FunctionParameter* parameters = NULL;
    int parameter_count = 0;
    int parameter_capacity = 0;
    
    if (!check(parser, TOKEN_RIGHT_PAREN)) {
        do {
            if (parameter_count >= parameter_capacity) {
                parameter_capacity = parameter_capacity == 0 ? 4 : parameter_capacity * 2;
                parameters = realloc(parameters, sizeof(FunctionParameter) * parameter_capacity);
                if (!parameters) {
                    parse_error(parser, "Out of memory");
                    free(name);
                    return NULL;
                }
            }
            
            Token param_name_token = consume(parser, TOKEN_IDENTIFIER, "Expected parameter name");
            consume(parser, TOKEN_COLON, "Expected ':' after parameter name");
            ZenType param_type = parse_type(parser);
            
            char* param_name = malloc(param_name_token.length + 1);
            if (!param_name) {
                parse_error(parser, "Out of memory");
                free(name);
                free(parameters);
                return NULL;
            }
            memcpy(param_name, param_name_token.start, param_name_token.length);
            param_name[param_name_token.length] = '\0';
            
            parameters[parameter_count].name = param_name;
            parameters[parameter_count].param_type = param_type;
            parameter_count++;
        } while (match(parser, TOKEN_COMMA));
    }
    
    consume(parser, TOKEN_RIGHT_PAREN, "Expected ')' after parameters");
    
    ZenType return_type = TYPE_VOID;
    if (match(parser, TOKEN_ARROW)) {
        return_type = parse_type(parser);
    }
    
    consume(parser, TOKEN_LEFT_BRACE, "Expected '{' before function body");
    ASTNode* body = parse_block_statement(parser);
    if (!body) {
        free(name);
        free(parameters);
        return NULL;
    }
    
    ASTNode* result = ast_create_function_declaration(parser->arena, name, parameters, parameter_count, return_type, body, name_token);
    free(name);
    return result;
}

ASTNode* parse_statement(Parser* parser) {
    if (match(parser, TOKEN_IF)) {
        return parse_if_statement(parser);
    }

    if (match(parser, TOKEN_RETURN)) {
        return parse_return_statement(parser);
    }
    
    if (match(parser, TOKEN_LEFT_BRACE)) {
        return parse_block_statement(parser);
    }
    
    // Handle variable declarations in statements
    if (match(parser, TOKEN_LET) || match(parser, TOKEN_CONST)) {
        return parse_var_declaration(parser);
    }
    
    return parse_expression_statement(parser);
}

ASTNode* parse_if_statement(Parser* parser) {
    Token if_token = parser->previous;
    consume(parser, TOKEN_LEFT_PAREN, "Expected '(' after 'if'.");
    ASTNode* condition = parse_expression(parser);
    consume(parser, TOKEN_RIGHT_PAREN, "Expected ')' after if condition.");

    ASTNode* then_branch = parse_statement(parser);
    ASTNode* else_branch = NULL;

    if (match(parser, TOKEN_ELSE)) {
        else_branch = parse_statement(parser);
    }

    return ast_create_if_stmt(parser->arena, condition, then_branch, else_branch, if_token);
}

ASTNode* parse_declaration(Parser* parser) {
    if (match(parser, TOKEN_FUNC)) {
        return parse_function_declaration(parser);
    }
    
    if (match(parser, TOKEN_LET) || match(parser, TOKEN_CONST)) {
        return parse_var_declaration(parser);
    }
    
    return parse_statement(parser);
}

ASTNode* parse_program(Parser* parser) {
    ASTNode** declarations = NULL;
    int declaration_count = 0;
    int declaration_capacity = 0;
    
    while (!is_at_end(parser)) {
        if (parser->panic_mode) synchronize(parser);
        
        // Skip newlines at top level
        if (match(parser, TOKEN_NEWLINE)) {
            continue;
        }
        
        if (declaration_count >= declaration_capacity) {
            declaration_capacity = declaration_capacity == 0 ? 4 : declaration_capacity * 2;
            declarations = realloc(declarations, sizeof(ASTNode*) * declaration_capacity);
            if (!declarations) {
                parse_error(parser, "Out of memory");
                return NULL;
            }
        }
        
        ASTNode* decl = parse_declaration(parser);
        if (decl) {
            declarations[declaration_count++] = decl;
        }
    }
    
    return ast_create_program(parser->arena, declarations, declaration_count);
}