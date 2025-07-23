#include "codegen.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>

#define INITIAL_BUFFER_SIZE 4096

CodeGen* codegen_create(CompileTarget target) {
    CodeGen* codegen = malloc(sizeof(CodeGen));
    if (!codegen) return NULL;
    
    codegen->target = target;
    codegen->output_buffer = malloc(INITIAL_BUFFER_SIZE);
    if (!codegen->output_buffer) {
        free(codegen);
        return NULL;
    }
    
    codegen->buffer_size = 0;
    codegen->buffer_capacity = INITIAL_BUFFER_SIZE;
    codegen->indent_level = 0;
    codegen->had_error = false;
    codegen->error_message = NULL;
    
    // Initialize buffer with empty string
    codegen->output_buffer[0] = '\0';
    
    return codegen;
}

void codegen_destroy(CodeGen* codegen) {
    if (!codegen) return;
    
    if (codegen->output_buffer) {
        free(codegen->output_buffer);
    }
    
    if (codegen->error_message) {
        free(codegen->error_message);
    }
    
    free(codegen);
}

bool codegen_append(CodeGen* codegen, const char* code) {
    if (!codegen || !code) return false;
    
    size_t code_len = strlen(code);
    size_t needed_size = codegen->buffer_size + code_len + 1;
    
    if (needed_size > codegen->buffer_capacity) {
        size_t new_capacity = codegen->buffer_capacity;
        while (new_capacity < needed_size) {
            new_capacity *= 2;
        }
        
        char* new_buffer = realloc(codegen->output_buffer, new_capacity);
        if (!new_buffer) {
            codegen_error(codegen, "Out of memory during code generation");
            return false;
        }
        
        codegen->output_buffer = new_buffer;
        codegen->buffer_capacity = new_capacity;
    }
    
    strcpy(codegen->output_buffer + codegen->buffer_size, code);
    codegen->buffer_size += code_len;
    
    return true;
}

bool codegen_append_formatted(CodeGen* codegen, const char* format, ...) {
    va_list args;
    va_start(args, format);
    
    // First, calculate how much space we need
    va_list args_copy;
    va_copy(args_copy, args);
    int needed = vsnprintf(NULL, 0, format, args_copy);
    va_end(args_copy);
    
    if (needed < 0) {
        va_end(args);
        codegen_error(codegen, "Error formatting string");
        return false;
    }
    
    // Allocate temporary buffer
    char* temp = malloc(needed + 1);
    if (!temp) {
        va_end(args);
        codegen_error(codegen, "Out of memory during formatting");
        return false;
    }
    
    vsnprintf(temp, needed + 1, format, args);
    va_end(args);
    
    bool result = codegen_append(codegen, temp);
    free(temp);
    
    return result;
}

void codegen_indent(CodeGen* codegen) {
    for (int i = 0; i < codegen->indent_level; i++) {
        codegen_append(codegen, "    ");
    }
}

void codegen_newline(CodeGen* codegen) {
    codegen_append(codegen, "\n");
}

void codegen_error(CodeGen* codegen, const char* message) {
    if (!codegen) return;
    
    codegen->had_error = true;
    
    if (codegen->error_message) {
        free(codegen->error_message);
    }
    
    codegen->error_message = malloc(strlen(message) + 1);
    if (codegen->error_message) {
        strcpy(codegen->error_message, message);
    }
    
    fprintf(stderr, "Code generation error: %s\n", message);
}

void codegen_error_formatted(CodeGen* codegen, const char* format, ...) {
    va_list args;
    va_start(args, format);
    
    // Calculate space needed
    va_list args_copy;
    va_copy(args_copy, args);
    int needed = vsnprintf(NULL, 0, format, args_copy);
    va_end(args_copy);
    
    if (needed < 0) {
        va_end(args);
        codegen_error(codegen, "Error formatting error message");
        return;
    }
    
    char* message = malloc(needed + 1);
    if (!message) {
        va_end(args);
        codegen_error(codegen, "Out of memory during error formatting");
        return;
    }
    
    vsnprintf(message, needed + 1, format, args);
    va_end(args);
    
    codegen_error(codegen, message);
    free(message);
}

const char* codegen_get_c_type(ZenType type) {
    switch (type) {
        case TYPE_I32: return "int";
        case TYPE_F64: return "double";
        case TYPE_STRING: return "char*";
        case TYPE_BOOL: return "bool";
        case TYPE_VOID: return "void";
        default: return "void";
    }
}

const char* codegen_get_binary_operator(BinaryOperator op) {
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
        case BINARY_IS: return "=="; // For now, treat 'is' as equality
        default: return "+";
    }
}

const char* codegen_get_unary_operator(UnaryOperator op) {
    switch (op) {
        case UNARY_MINUS: return "-";
        case UNARY_NOT: return "!";
        default: return "-";
    }
}

// Symbol table management
SymbolTable* symbol_table_create(SymbolTable* parent) {
    SymbolTable* table = malloc(sizeof(SymbolTable));
    if (!table) return NULL;
    
    table->symbols = NULL;
    table->parent = parent;
    
    return table;
}

void symbol_table_destroy(SymbolTable* table) {
    if (!table) return;
    
    Symbol* current = table->symbols;
    while (current) {
        Symbol* next = current->next;
        if (current->name) free(current->name);
        free(current);
        current = next;
    }
    
    free(table);
}

Symbol* symbol_table_add(SymbolTable* table, const char* name, ZenType type, bool is_function, bool is_const) {
    if (!table || !name) return NULL;
    
    Symbol* symbol = malloc(sizeof(Symbol));
    if (!symbol) return NULL;
    
    symbol->name = malloc(strlen(name) + 1);
    if (!symbol->name) {
        free(symbol);
        return NULL;
    }
    strcpy(symbol->name, name);
    
    symbol->type = type;
    symbol->is_function = is_function;
    symbol->is_const = is_const;
    symbol->stack_offset = 0; // TODO: Calculate proper offset
    symbol->next = table->symbols;
    
    table->symbols = symbol;
    
    return symbol;
}

Symbol* symbol_table_lookup(SymbolTable* table, const char* name) {
    if (!table || !name) return NULL;
    
    // Search current scope
    Symbol* current = table->symbols;
    while (current) {
        if (strcmp(current->name, name) == 0) {
            return current;
        }
        current = current->next;
    }
    
    // Search parent scope
    if (table->parent) {
        return symbol_table_lookup(table->parent, name);
    }
    
    return NULL;
}

// Code generation functions
bool codegen_generate(CodeGen* codegen, ASTNode* program) {
    if (!codegen || !program) {
        codegen_error(codegen, "Invalid arguments to codegen_generate");
        return false;
    }
    
    if (program->type != AST_PROGRAM) {
        codegen_error(codegen, "Expected program node");
        return false;
    }
    
    // Generate C header includes
    codegen_append(codegen, "#include <stdio.h>\n");
    codegen_append(codegen, "#include <stdlib.h>\n");
    codegen_append(codegen, "#include <stdbool.h>\n");
    codegen_append(codegen, "#include <string.h>\n");
    codegen_newline(codegen);
    
    return codegen_program(codegen, (ASTProgram*)program);
}

bool codegen_program(CodeGen* codegen, ASTProgram* program) {
    if (!codegen || !program) return false;
    
    for (int i = 0; i < program->declaration_count; i++) {
        if (!codegen_statement(codegen, program->declarations[i])) {
            return false;
        }
        codegen_newline(codegen);
    }
    
    return true;
}

bool codegen_function_declaration(CodeGen* codegen, ASTFunctionDeclaration* func) {
    if (!codegen || !func) return false;
    
    // Function signature
    codegen_append_formatted(codegen, "%s %s(", 
                             codegen_get_c_type(func->return_type), 
                             func->name);
    
    // Parameters
    for (int i = 0; i < func->parameter_count; i++) {
        if (i > 0) codegen_append(codegen, ", ");
        codegen_append_formatted(codegen, "%s %s", 
                                 codegen_get_c_type(func->parameters[i].param_type),
                                 func->parameters[i].name);
    }
    
    if (func->parameter_count == 0) {
        codegen_append(codegen, "void");
    }
    
    codegen_append(codegen, ") ");
    
    // Function body
    if (!codegen_statement(codegen, func->body)) {
        return false;
    }
    
    return true;
}

bool codegen_variable_declaration(CodeGen* codegen, ASTVarDeclaration* var) {
    if (!codegen || !var) return false;
    
    codegen_indent(codegen);
    
    // Determine C type
    const char* c_type = "int"; // Default
    if (var->var_type != TYPE_UNKNOWN) {
        c_type = codegen_get_c_type(var->var_type);
    }
    
    // Add const qualifier if needed
    if (var->is_const) {
        codegen_append(codegen, "const ");
    }
    
    codegen_append_formatted(codegen, "%s %s", c_type, var->name);
    
    // Initializer
    if (var->initializer) {
        codegen_append(codegen, " = ");
        if (!codegen_expression(codegen, var->initializer)) {
            return false;
        }
    }
    
    codegen_append(codegen, ";");
    codegen_newline(codegen);
    
    return true;
}

bool codegen_statement(CodeGen* codegen, ASTNode* stmt) {
    if (!codegen || !stmt) return false;
    
    switch (stmt->type) {
        case AST_FUNCTION_DECLARATION:
            return codegen_function_declaration(codegen, (ASTFunctionDeclaration*)stmt);
            
        case AST_VAR_DECLARATION:
            return codegen_variable_declaration(codegen, (ASTVarDeclaration*)stmt);
            
        case AST_BLOCK_STMT:
            return codegen_block_stmt(codegen, (ASTBlockStmt*)stmt);
            
        case AST_EXPRESSION_STMT:
            return codegen_expression_stmt(codegen, (ASTExpressionStmt*)stmt);
            
        case AST_RETURN_STMT:
            return codegen_return_stmt(codegen, (ASTReturnStmt*)stmt);
            
        default:
            codegen_error_formatted(codegen, "Unsupported statement type: %s", 
                                   ast_node_type_to_string(stmt->type));
            return false;
    }
}

bool codegen_block_stmt(CodeGen* codegen, ASTBlockStmt* block) {
    if (!codegen || !block) return false;
    
    codegen_append(codegen, "{");
    codegen_newline(codegen);
    codegen->indent_level++;
    
    for (int i = 0; i < block->statement_count; i++) {
        if (!codegen_statement(codegen, block->statements[i])) {
            return false;
        }
    }
    
    codegen->indent_level--;
    codegen_indent(codegen);
    codegen_append(codegen, "}");
    
    return true;
}

bool codegen_expression_stmt(CodeGen* codegen, ASTExpressionStmt* expr_stmt) {
    if (!codegen || !expr_stmt) return false;
    
    codegen_indent(codegen);
    if (!codegen_expression(codegen, expr_stmt->expression)) {
        return false;
    }
    codegen_append(codegen, ";");
    codegen_newline(codegen);
    
    return true;
}

bool codegen_return_stmt(CodeGen* codegen, ASTReturnStmt* ret_stmt) {
    if (!codegen || !ret_stmt) return false;
    
    codegen_indent(codegen);
    codegen_append(codegen, "return");
    
    if (ret_stmt->value) {
        codegen_append(codegen, " ");
        if (!codegen_expression(codegen, ret_stmt->value)) {
            return false;
        }
    }
    
    codegen_append(codegen, ";");
    codegen_newline(codegen);
    
    return true;
}

bool codegen_expression(CodeGen* codegen, ASTNode* expr) {
    if (!codegen || !expr) return false;
    
    switch (expr->type) {
        case AST_LITERAL_EXPR:
            return codegen_literal(codegen, (ASTLiteralExpr*)expr);
            
        case AST_IDENTIFIER_EXPR:
            return codegen_identifier(codegen, (ASTIdentifierExpr*)expr);
            
        case AST_BINARY_EXPR:
            return codegen_binary_expr(codegen, (ASTBinaryExpr*)expr);
            
        case AST_UNARY_EXPR:
            return codegen_unary_expr(codegen, (ASTUnaryExpr*)expr);
            
        case AST_CALL_EXPR:
            return codegen_call_expr(codegen, (ASTCallExpr*)expr);
            
        default:
            codegen_error_formatted(codegen, "Unsupported expression type: %s", 
                                   ast_node_type_to_string(expr->type));
            return false;
    }
}

bool codegen_literal(CodeGen* codegen, ASTLiteralExpr* literal) {
    if (!codegen || !literal) return false;
    
    switch (literal->literal_type) {
        case LITERAL_NUMBER:
            codegen_append_formatted(codegen, "%.6g", literal->value.number_value);
            break;
            
        case LITERAL_STRING:
            codegen_append_formatted(codegen, "\"%s\"", 
                                   literal->value.string_value ? literal->value.string_value : "");
            break;
            
        case LITERAL_BOOLEAN:
            codegen_append(codegen, literal->value.boolean_value ? "true" : "false");
            break;
            
        case LITERAL_NULL:
            codegen_append(codegen, "NULL");
            break;
            
        default:
            codegen_error(codegen, "Unknown literal type");
            return false;
    }
    
    return true;
}

bool codegen_identifier(CodeGen* codegen, ASTIdentifierExpr* ident) {
    if (!codegen || !ident) return false;
    
    codegen_append(codegen, ident->name);
    return true;
}

bool codegen_binary_expr(CodeGen* codegen, ASTBinaryExpr* binary) {
    if (!codegen || !binary) return false;
    
    codegen_append(codegen, "(");
    
    if (!codegen_expression(codegen, binary->left)) {
        return false;
    }
    
    codegen_append_formatted(codegen, " %s ", codegen_get_binary_operator(binary->operator));
    
    if (!codegen_expression(codegen, binary->right)) {
        return false;
    }
    
    codegen_append(codegen, ")");
    
    return true;
}

bool codegen_unary_expr(CodeGen* codegen, ASTUnaryExpr* unary) {
    if (!codegen || !unary) return false;
    
    codegen_append_formatted(codegen, "%s(", codegen_get_unary_operator(unary->operator));
    
    if (!codegen_expression(codegen, unary->operand)) {
        return false;
    }
    
    codegen_append(codegen, ")");
    
    return true;
}

bool codegen_call_expr(CodeGen* codegen, ASTCallExpr* call) {
    if (!codegen || !call) return false;
    
    // Check for built-in functions
    if (call->callee->type == AST_IDENTIFIER_EXPR) {
        ASTIdentifierExpr* ident = (ASTIdentifierExpr*)call->callee;
        
        if (strcmp(ident->name, "print") == 0) {
            return codegen_builtin_print(codegen, call);
        }
    }
    
    // Regular function call
    if (!codegen_expression(codegen, call->callee)) {
        return false;
    }
    
    codegen_append(codegen, "(");
    
    for (int i = 0; i < call->argument_count; i++) {
        if (i > 0) codegen_append(codegen, ", ");
        if (!codegen_expression(codegen, call->arguments[i])) {
            return false;
        }
    }
    
    codegen_append(codegen, ")");
    
    return true;
}

bool codegen_builtin_print(CodeGen* codegen, ASTCallExpr* call) {
    if (!codegen || !call) return false;
    
    codegen_append(codegen, "printf(");
    
    if (call->argument_count > 0) {
        // For now, assume first argument and treat as string or number
        ASTNode* arg = call->arguments[0];
        
        if (arg->type == AST_LITERAL_EXPR) {
            ASTLiteralExpr* literal = (ASTLiteralExpr*)arg;
            if (literal->literal_type == LITERAL_STRING) {
                codegen_append(codegen, "\"%s\\n\", ");
                if (!codegen_expression(codegen, arg)) {
                    return false;
                }
            } else if (literal->literal_type == LITERAL_NUMBER) {
                codegen_append(codegen, "\"%.6g\\n\", ");
                if (!codegen_expression(codegen, arg)) {
                    return false;
                }
            } else {
                codegen_append(codegen, "\"%s\\n\", ");
                if (!codegen_expression(codegen, arg)) {
                    return false;
                }
            }
        } else {
            // Default to %s format
            codegen_append(codegen, "\"%s\\n\", ");
            if (!codegen_expression(codegen, arg)) {
                return false;
            }
        }
    } else {
        codegen_append(codegen, "\"\\n\"");
    }
    
    codegen_append(codegen, ")");
    
    return true;
}