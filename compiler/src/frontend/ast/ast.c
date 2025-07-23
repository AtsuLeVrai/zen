#include "ast.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#define INITIAL_ARENA_CAPACITY 64

ASTArena* ast_arena_create(void) {
    ASTArena* arena = malloc(sizeof(ASTArena));
    if (!arena) return NULL;
    
    arena->nodes = malloc(sizeof(ASTNode*) * INITIAL_ARENA_CAPACITY);
    if (!arena->nodes) {
        free(arena);
        return NULL;
    }
    
    arena->count = 0;
    arena->capacity = INITIAL_ARENA_CAPACITY;
    return arena;
}

void ast_arena_destroy(ASTArena* arena) {
    if (!arena) return;
    
    // Free all nodes
    for (int i = 0; i < arena->count; i++) {
        ASTNode* node = arena->nodes[i];
        if (!node) continue;
        
        // Free node-specific data
        switch (node->type) {
            case AST_LITERAL_EXPR: {
                const ASTLiteralExpr* literal = (ASTLiteralExpr*)node;
                if (literal->literal_type == LITERAL_STRING && literal->value.string_value) {
                    free(literal->value.string_value);
                }
                break;
            }
            case AST_IDENTIFIER_EXPR: {
                const ASTIdentifierExpr* ident = (ASTIdentifierExpr*)node;
                if (ident->name) free(ident->name);
                break;
            }
            case AST_CALL_EXPR: {
                const ASTCallExpr* call = (ASTCallExpr*)node;
                if (call->arguments) free(call->arguments);
                break;
            }
            case AST_VAR_DECLARATION: {
                const ASTVarDeclaration* var = (ASTVarDeclaration*)node;
                if (var->name) free(var->name);
                break;
            }
            case AST_FUNCTION_DECLARATION: {
                const ASTFunctionDeclaration* func = (ASTFunctionDeclaration*)node;
                if (func->name) free(func->name);
                if (func->parameters) {
                    for (int j = 0; j < func->parameter_count; j++) {
                        if (func->parameters[j].name) {
                            free(func->parameters[j].name);
                        }
                    }
                    free(func->parameters);
                }
                break;
            }
            case AST_BLOCK_STMT: {
                const ASTBlockStmt* block = (ASTBlockStmt*)node;
                if (block->statements) free(block->statements);
                break;
            }
            case AST_FOR_STMT: {
                const ASTForStmt* for_stmt = (ASTForStmt*)node;
                if (for_stmt->variable) free(for_stmt->variable);
                break;
            }
            case AST_PROGRAM: {
                const ASTProgram* program = (ASTProgram*)node;
                if (program->declarations) free(program->declarations);
                break;
            }
            default:
                break;
        }
        
        free(node);
    }
    
    free(arena->nodes);
    free(arena);
}

void ast_arena_add(ASTArena* arena, ASTNode* node) {
    if (!arena || !node) return;
    
    if (arena->count >= arena->capacity) {
        arena->capacity *= 2;
        arena->nodes = realloc(arena->nodes, sizeof(ASTNode*) * arena->capacity);
        if (!arena->nodes) {
            fprintf(stderr, "Failed to reallocate AST arena\n");
            exit(1);
        }
    }
    
    arena->nodes[arena->count++] = node;
}

// Helper function to duplicate a string
static char* duplicate_string(const char* str) {
    if (!str) return NULL;

    const size_t len = strlen(str);
    char* copy = malloc(len + 1);
    if (!copy) return NULL;
    
    strcpy(copy, str);
    return copy;
}

ASTNode* ast_create_literal_number(ASTArena* arena, double value, Token token) {
    ASTLiteralExpr* node = malloc(sizeof(ASTLiteralExpr));
    if (!node) return NULL;
    
    node->base.type = AST_LITERAL_EXPR;
    node->base.token = token;
    node->base.line = token.line;
    node->base.column = token.column;
    node->literal_type = LITERAL_NUMBER;
    node->value.number_value = value;
    
    ast_arena_add(arena, (ASTNode*)node);
    return (ASTNode*)node;
}

ASTNode* ast_create_literal_string(ASTArena* arena, const char* value, Token token) {
    ASTLiteralExpr* node = malloc(sizeof(ASTLiteralExpr));
    if (!node) return NULL;
    
    node->base.type = AST_LITERAL_EXPR;
    node->base.token = token;
    node->base.line = token.line;
    node->base.column = token.column;
    node->literal_type = LITERAL_STRING;
    node->value.string_value = duplicate_string(value);
    
    ast_arena_add(arena, (ASTNode*)node);
    return (ASTNode*)node;
}

ASTNode* ast_create_literal_boolean(ASTArena* arena, bool value, Token token) {
    ASTLiteralExpr* node = malloc(sizeof(ASTLiteralExpr));
    if (!node) return NULL;
    
    node->base.type = AST_LITERAL_EXPR;
    node->base.token = token;
    node->base.line = token.line;
    node->base.column = token.column;
    node->literal_type = LITERAL_BOOLEAN;
    node->value.boolean_value = value;
    
    ast_arena_add(arena, (ASTNode*)node);
    return (ASTNode*)node;
}

ASTNode* ast_create_literal_null(ASTArena* arena, Token token) {
    ASTLiteralExpr* node = malloc(sizeof(ASTLiteralExpr));
    if (!node) return NULL;
    
    node->base.type = AST_LITERAL_EXPR;
    node->base.token = token;
    node->base.line = token.line;
    node->base.column = token.column;
    node->literal_type = LITERAL_NULL;
    
    ast_arena_add(arena, (ASTNode*)node);
    return (ASTNode*)node;
}

ASTNode* ast_create_identifier(ASTArena* arena, const char* name, Token token) {
    ASTIdentifierExpr* node = malloc(sizeof(ASTIdentifierExpr));
    if (!node) return NULL;
    
    node->base.type = AST_IDENTIFIER_EXPR;
    node->base.token = token;
    node->base.line = token.line;
    node->base.column = token.column;
    node->name = duplicate_string(name);
    
    ast_arena_add(arena, (ASTNode*)node);
    return (ASTNode*)node;
}

ASTNode* ast_create_binary_expr(ASTArena* arena, BinaryOperator op, ASTNode* left, ASTNode* right, Token token) {
    ASTBinaryExpr* node = malloc(sizeof(ASTBinaryExpr));
    if (!node) return NULL;
    
    node->base.type = AST_BINARY_EXPR;
    node->base.token = token;
    node->base.line = token.line;
    node->base.column = token.column;
    node->operator = op;
    node->left = left;
    node->right = right;
    
    ast_arena_add(arena, (ASTNode*)node);
    return (ASTNode*)node;
}

ASTNode* ast_create_unary_expr(ASTArena* arena, UnaryOperator op, ASTNode* operand, Token token) {
    ASTUnaryExpr* node = malloc(sizeof(ASTUnaryExpr));
    if (!node) return NULL;
    
    node->base.type = AST_UNARY_EXPR;
    node->base.token = token;
    node->base.line = token.line;
    node->base.column = token.column;
    node->operator = op;
    node->operand = operand;
    
    ast_arena_add(arena, (ASTNode*)node);
    return (ASTNode*)node;
}

ASTNode* ast_create_call_expr(ASTArena* arena, ASTNode* callee, ASTNode** args, int arg_count, Token token) {
    ASTCallExpr* node = malloc(sizeof(ASTCallExpr));
    if (!node) return NULL;
    
    node->base.type = AST_CALL_EXPR;
    node->base.token = token;
    node->base.line = token.line;
    node->base.column = token.column;
    node->callee = callee;
    node->arguments = args;
    node->argument_count = arg_count;
    
    ast_arena_add(arena, (ASTNode*)node);
    return (ASTNode*)node;
}

ASTNode* ast_create_var_declaration(ASTArena* arena, const char* name, ZenType type, bool is_const, ASTNode* init, Token token) {
    ASTVarDeclaration* node = malloc(sizeof(ASTVarDeclaration));
    if (!node) return NULL;
    
    node->base.type = AST_VAR_DECLARATION;
    node->base.token = token;
    node->base.line = token.line;
    node->base.column = token.column;
    node->name = duplicate_string(name);
    node->var_type = type;
    node->is_const = is_const;
    node->initializer = init;
    
    ast_arena_add(arena, (ASTNode*)node);
    return (ASTNode*)node;
}

ASTNode* ast_create_function_declaration(ASTArena* arena, const char* name, FunctionParameter* params, int param_count, ZenType return_type, ASTNode* body, Token token) {
    ASTFunctionDeclaration* node = malloc(sizeof(ASTFunctionDeclaration));
    if (!node) return NULL;
    
    node->base.type = AST_FUNCTION_DECLARATION;
    node->base.token = token;
    node->base.line = token.line;
    node->base.column = token.column;
    node->name = duplicate_string(name);
    node->parameters = params;
    node->parameter_count = param_count;
    node->return_type = return_type;
    node->body = body;
    
    ast_arena_add(arena, (ASTNode*)node);
    return (ASTNode*)node;
}

ASTNode* ast_create_return_stmt(ASTArena* arena, ASTNode* value, Token token) {
    ASTReturnStmt* node = malloc(sizeof(ASTReturnStmt));
    if (!node) return NULL;
    
    node->base.type = AST_RETURN_STMT;
    node->base.token = token;
    node->base.line = token.line;
    node->base.column = token.column;
    node->value = value;
    
    ast_arena_add(arena, (ASTNode*)node);
    return (ASTNode*)node;
}

ASTNode* ast_create_block_stmt(ASTArena* arena, ASTNode** statements, int count, Token token) {
    ASTBlockStmt* node = malloc(sizeof(ASTBlockStmt));
    if (!node) return NULL;
    
    node->base.type = AST_BLOCK_STMT;
    node->base.token = token;
    node->base.line = token.line;
    node->base.column = token.column;
    node->statements = statements;
    node->statement_count = count;
    
    ast_arena_add(arena, (ASTNode*)node);
    return (ASTNode*)node;
}

ASTNode* ast_create_expression_stmt(ASTArena* arena, ASTNode* expr, Token token) {
    ASTExpressionStmt* node = malloc(sizeof(ASTExpressionStmt));
    if (!node) return NULL;
    
    node->base.type = AST_EXPRESSION_STMT;
    node->base.token = token;
    node->base.line = token.line;
    node->base.column = token.column;
    node->expression = expr;
    
    ast_arena_add(arena, (ASTNode*)node);
    return (ASTNode*)node;
}

ASTNode* ast_create_if_stmt(ASTArena* arena, ASTNode* condition, ASTNode* then_branch, ASTNode* else_branch, Token token) {
    ASTIfStmt* node = malloc(sizeof(ASTIfStmt));
    if (!node) return NULL;
    
    node->base.type = AST_IF_STMT;
    node->base.token = token;
    node->base.line = token.line;
    node->base.column = token.column;
    node->condition = condition;
    node->then_branch = then_branch;
    node->else_branch = else_branch;
    
    ast_arena_add(arena, (ASTNode*)node);
    return (ASTNode*)node;
}

ASTNode* ast_create_while_stmt(ASTArena* arena, ASTNode* condition, ASTNode* body, Token token) {
    ASTWhileStmt* node = malloc(sizeof(ASTWhileStmt));
    if (!node) return NULL;
    
    node->base.type = AST_WHILE_STMT;
    node->base.token = token;
    node->base.line = token.line;
    node->base.column = token.column;
    node->condition = condition;
    node->body = body;
    
    ast_arena_add(arena, (ASTNode*)node);
    return (ASTNode*)node;
}

ASTNode* ast_create_for_stmt(ASTArena* arena, const char* variable, ASTNode* iterable, ASTNode* body, Token token) {
    ASTForStmt* node = malloc(sizeof(ASTForStmt));
    if (!node) return NULL;
    
    node->base.type = AST_FOR_STMT;
    node->base.token = token;
    node->base.line = token.line;
    node->base.column = token.column;
    node->variable = duplicate_string(variable);
    node->iterable = iterable;
    node->body = body;
    
    ast_arena_add(arena, (ASTNode*)node);
    return (ASTNode*)node;
}

ASTNode* ast_create_program(ASTArena* arena, ASTNode** declarations, int count) {
    ASTProgram* node = malloc(sizeof(ASTProgram));
    if (!node) return NULL;
    
    Token dummy_token = {TOKEN_EOF, "", 0, 1, 1};
    node->base.type = AST_PROGRAM;
    node->base.token = dummy_token;
    node->base.line = 1;
    node->base.column = 1;
    node->declarations = declarations;
    node->declaration_count = count;
    
    ast_arena_add(arena, (ASTNode*)node);
    return (ASTNode*)node;
}

// Utility functions
const char* ast_node_type_to_string(ASTNodeType type) {
    switch (type) {
        case AST_LITERAL_EXPR: return "LITERAL_EXPR";
        case AST_IDENTIFIER_EXPR: return "IDENTIFIER_EXPR";
        case AST_BINARY_EXPR: return "BINARY_EXPR";
        case AST_UNARY_EXPR: return "UNARY_EXPR";
        case AST_CALL_EXPR: return "CALL_EXPR";
        case AST_INTERPOLATION_EXPR: return "INTERPOLATION_EXPR";
        case AST_EXPRESSION_STMT: return "EXPRESSION_STMT";
        case AST_VAR_DECLARATION: return "VAR_DECLARATION";
        case AST_FUNCTION_DECLARATION: return "FUNCTION_DECLARATION";
        case AST_RETURN_STMT: return "RETURN_STMT";
        case AST_BLOCK_STMT: return "BLOCK_STMT";
        case AST_IF_STMT: return "IF_STMT";
        case AST_WHILE_STMT: return "WHILE_STMT";
        case AST_FOR_STMT: return "FOR_STMT";
        case AST_PROGRAM: return "PROGRAM";
        default: return "UNKNOWN";
    }
}

const char* binary_operator_to_string(BinaryOperator op) {
    switch (op) {
        case BINARY_ADD: return "+";
        case BINARY_SUBTRACT: return "-";
        case BINARY_MULTIPLY: return "*";
        case BINARY_DIVIDE: return "/";
        case BINARY_MODULO: return "%";
        case BINARY_EQUAL: return "==";
        case BINARY_NOT_EQUAL: return "!=";
        case BINARY_LESS: return "<";
        case BINARY_LESS_EQUAL: return "<=";
        case BINARY_GREATER: return ">";
        case BINARY_GREATER_EQUAL: return ">=";
        case BINARY_AND: return "&&";
        case BINARY_OR: return "||";
        case BINARY_IS: return "is";
        default: return "UNKNOWN";
    }
}

const char* unary_operator_to_string(UnaryOperator op) {
    switch (op) {
        case UNARY_MINUS: return "-";
        case UNARY_NOT: return "!";
        default: return "UNKNOWN";
    }
}

const char* zen_type_to_string(ZenType type) {
    switch (type) {
        case TYPE_I32: return "i32";
        case TYPE_F64: return "f64";
        case TYPE_STRING: return "string";
        case TYPE_BOOL: return "bool";
        case TYPE_VOID: return "void";
        case TYPE_UNKNOWN: return "unknown";
        default: return "INVALID";
    }
}

ZenType token_type_to_zen_type(TokenType token_type) {
    switch (token_type) {
        case TOKEN_I32: return TYPE_I32;
        case TOKEN_F64: return TYPE_F64;
        case TOKEN_STRING_TYPE: return TYPE_STRING;
        case TOKEN_BOOL: return TYPE_BOOL;
        case TOKEN_VOID: return TYPE_VOID;
        default: return TYPE_UNKNOWN;
    }
}

BinaryOperator token_type_to_binary_operator(TokenType token_type) {
    switch (token_type) {
        case TOKEN_PLUS: return BINARY_ADD;
        case TOKEN_MINUS: return BINARY_SUBTRACT;
        case TOKEN_MULTIPLY: return BINARY_MULTIPLY;
        case TOKEN_DIVIDE: return BINARY_DIVIDE;
        case TOKEN_MODULO: return BINARY_MODULO;
        case TOKEN_EQUAL: return BINARY_EQUAL;
        case TOKEN_NOT_EQUAL: return BINARY_NOT_EQUAL;
        case TOKEN_LESS: return BINARY_LESS;
        case TOKEN_LESS_EQUAL: return BINARY_LESS_EQUAL;
        case TOKEN_GREATER: return BINARY_GREATER;
        case TOKEN_GREATER_EQUAL: return BINARY_GREATER_EQUAL;
        case TOKEN_AND: return BINARY_AND;
        case TOKEN_OR: return BINARY_OR;
        case TOKEN_IS: return BINARY_IS;
        default: return BINARY_ADD; // Default fallback
    }
}

UnaryOperator token_type_to_unary_operator(TokenType token_type) {
    switch (token_type) {
        case TOKEN_MINUS: return UNARY_MINUS;
        case TOKEN_NOT: return UNARY_NOT;
        default: return UNARY_MINUS; // Default fallback
    }
}

// AST printing for debugging
static void print_indent(int indent) {
    for (int i = 0; i < indent; i++) {
        printf("  ");
    }
}

void ast_print(ASTNode* node, int indent) {
    if (!node) {
        print_indent(indent);
        printf("(null)\n");
        return;
    }
    
    print_indent(indent);
    
    switch (node->type) {
        case AST_LITERAL_EXPR: {
            ASTLiteralExpr* literal = (ASTLiteralExpr*)node;
            printf("LITERAL: ");
            switch (literal->literal_type) {
                case LITERAL_NUMBER:
                    printf("%.2f\n", literal->value.number_value);
                    break;
                case LITERAL_STRING:
                    printf("\"%s\"\n", literal->value.string_value ? literal->value.string_value : "(null)");
                    break;
                case LITERAL_BOOLEAN:
                    printf("%s\n", literal->value.boolean_value ? "true" : "false");
                    break;
                case LITERAL_NULL:
                    printf("null\n");
                    break;
            }
            break;
        }
        
        case AST_IDENTIFIER_EXPR: {
            ASTIdentifierExpr* ident = (ASTIdentifierExpr*)node;
            printf("IDENTIFIER: %s\n", ident->name ? ident->name : "(null)");
            break;
        }
        
        case AST_BINARY_EXPR: {
            ASTBinaryExpr* binary = (ASTBinaryExpr*)node;
            printf("BINARY_EXPR: %s\n", binary_operator_to_string(binary->operator));
            ast_print(binary->left, indent + 1);
            ast_print(binary->right, indent + 1);
            break;
        }
        
        case AST_UNARY_EXPR: {
            ASTUnaryExpr* unary = (ASTUnaryExpr*)node;
            printf("UNARY_EXPR: %s\n", unary_operator_to_string(unary->operator));
            ast_print(unary->operand, indent + 1);
            break;
        }
        
        case AST_CALL_EXPR: {
            ASTCallExpr* call = (ASTCallExpr*)node;
            printf("CALL_EXPR:\n");
            print_indent(indent + 1);
            printf("Callee:\n");
            ast_print(call->callee, indent + 2);
            print_indent(indent + 1);
            printf("Arguments (%d):\n", call->argument_count);
            for (int i = 0; i < call->argument_count; i++) {
                ast_print(call->arguments[i], indent + 2);
            }
            break;
        }
        
        case AST_VAR_DECLARATION: {
            ASTVarDeclaration* var = (ASTVarDeclaration*)node;
            printf("VAR_DECLARATION: %s %s: %s\n", 
                   var->is_const ? "const" : "let",
                   var->name ? var->name : "(null)",
                   zen_type_to_string(var->var_type));
            if (var->initializer) {
                print_indent(indent + 1);
                printf("Initializer:\n");
                ast_print(var->initializer, indent + 2);
            }
            break;
        }
        
        case AST_FUNCTION_DECLARATION: {
            ASTFunctionDeclaration* func = (ASTFunctionDeclaration*)node;
            printf("FUNCTION_DECLARATION: %s -> %s\n",
                   func->name ? func->name : "(null)",
                   zen_type_to_string(func->return_type));
            print_indent(indent + 1);
            printf("Parameters (%d):\n", func->parameter_count);
            for (int i = 0; i < func->parameter_count; i++) {
                print_indent(indent + 2);
                printf("%s: %s\n", 
                       func->parameters[i].name ? func->parameters[i].name : "(null)",
                       zen_type_to_string(func->parameters[i].param_type));
            }
            print_indent(indent + 1);
            printf("Body:\n");
            ast_print(func->body, indent + 2);
            break;
        }
        
        case AST_RETURN_STMT: {
            ASTReturnStmt* ret = (ASTReturnStmt*)node;
            printf("RETURN_STMT:\n");
            if (ret->value) {
                ast_print(ret->value, indent + 1);
            }
            break;
        }
        
        case AST_BLOCK_STMT: {
            ASTBlockStmt* block = (ASTBlockStmt*)node;
            printf("BLOCK_STMT (%d statements):\n", block->statement_count);
            for (int i = 0; i < block->statement_count; i++) {
                ast_print(block->statements[i], indent + 1);
            }
            break;
        }
        
        case AST_EXPRESSION_STMT: {
            ASTExpressionStmt* expr_stmt = (ASTExpressionStmt*)node;
            printf("EXPRESSION_STMT:\n");
            ast_print(expr_stmt->expression, indent + 1);
            break;
        }
        
        case AST_PROGRAM: {
            ASTProgram* program = (ASTProgram*)node;
            printf("PROGRAM (%d declarations):\n", program->declaration_count);
            for (int i = 0; i < program->declaration_count; i++) {
                ast_print(program->declarations[i], indent + 1);
            }
            break;
        }
        
        default:
            printf("UNKNOWN_NODE_TYPE: %d\n", node->type);
            break;
    }
}