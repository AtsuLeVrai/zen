#include "native_codegen.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>

#ifdef _WIN32
#include <io.h>
#include <fcntl.h>
#define open _open
#define close _close
#define write _write
#define O_WRONLY _O_WRONLY
#define O_CREAT _O_CREAT
#define O_TRUNC _O_TRUNC
#else
#include <unistd.h>
#include <fcntl.h>
#endif

#define INITIAL_CODE_CAPACITY 4096
#define BASE_ADDRESS 0x400000

NativeCodeGen* native_codegen_create(void) {
    NativeCodeGen* codegen = malloc(sizeof(NativeCodeGen));
    if (!codegen) return NULL;
    
    codegen->instructions = NULL;
    codegen->last_instruction = NULL;
    codegen->string_literals = NULL;
    codegen->functions = NULL;
    codegen->variables = NULL;
    
    codegen->current_function = NULL;
    codegen->stack_offset = 0;
    codegen->label_counter = 0;
    
    codegen->code_buffer = malloc(INITIAL_CODE_CAPACITY);
    if (!codegen->code_buffer) {
        free(codegen);
        return NULL;
    }
    codegen->code_size = 0;
    codegen->code_capacity = INITIAL_CODE_CAPACITY;
    
    codegen->had_error = false;
    codegen->error_message = NULL;
    
    return codegen;
}

void native_codegen_destroy(NativeCodeGen* codegen) {
    if (!codegen) return;
    
    // Free instructions
    Instruction* inst = codegen->instructions;
    while (inst) {
        Instruction* next = inst->next;
        if (inst->label) free(inst->label);
        for (int i = 0; i < inst->operand_count; i++) {
            if (inst->operands[i].type == OPERAND_LABEL && inst->operands[i].value.label) {
                free(inst->operands[i].value.label);
            }
        }
        free(inst);
        inst = next;
    }
    
    // Free string literals
    StringLiteral* str = codegen->string_literals;
    while (str) {
        StringLiteral* next = str->next;
        if (str->label) free(str->label);
        if (str->content) free(str->content);
        free(str);
        str = next;
    }
    
    // Free function symbols
    FunctionSymbol* func = codegen->functions;
    while (func) {
        FunctionSymbol* next = func->next;
        if (func->name) free(func->name);
        if (func->label) free(func->label);
        free(func);
        func = next;
    }
    
    // Free variable symbols
    VariableSymbol* var = codegen->variables;
    while (var) {
        VariableSymbol* next = var->next;
        if (var->name) free(var->name);
        free(var);
        var = next;
    }
    
    if (codegen->code_buffer) free(codegen->code_buffer);
    if (codegen->current_function) free(codegen->current_function);
    if (codegen->error_message) free(codegen->error_message);
    
    free(codegen);
}

void native_codegen_error(NativeCodeGen* codegen, const char* message) {
    if (!codegen) return;
    
    codegen->had_error = true;
    if (codegen->error_message) free(codegen->error_message);
    
    codegen->error_message = malloc(strlen(message) + 1);
    if (codegen->error_message) {
        strcpy(codegen->error_message, message);
    }
    
    fprintf(stderr, "Native code generation error: %s\n", message);
}

const char* register_name(X86Register reg) {
    static const char* names[] = {
        "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi",
        "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15"
    };
    return names[reg];
}

int register_encoding(X86Register reg) {
    return reg & 0x7; // Lower 3 bits
}

bool is_register_extended(X86Register reg) {
    return reg >= REG_R8;
}

char* create_label(NativeCodeGen* codegen, const char* prefix) {
    char* label = malloc(64);
    if (!label) return NULL;
    
    snprintf(label, 64, "%s_%d", prefix, codegen->label_counter++);
    return label;
}

void emit_label(NativeCodeGen* codegen, const char* label) {
    Instruction* inst = malloc(sizeof(Instruction));
    if (!inst) {
        native_codegen_error(codegen, "Out of memory");
        return;
    }
    
    inst->opcode = INST_NOP; // Label marker
    inst->operand_count = 0;
    inst->label = malloc(strlen(label) + 1);
    strcpy(inst->label, label);
    inst->next = NULL;
    
    if (codegen->last_instruction) {
        codegen->last_instruction->next = inst;
    } else {
        codegen->instructions = inst;
    }
    codegen->last_instruction = inst;
}

void emit_instruction(NativeCodeGen* codegen, X86Instruction opcode) {
    Instruction* inst = malloc(sizeof(Instruction));
    if (!inst) {
        native_codegen_error(codegen, "Out of memory");
        return;
    }
    
    inst->opcode = opcode;
    inst->operand_count = 0;
    inst->label = NULL;
    inst->next = NULL;
    
    if (codegen->last_instruction) {
        codegen->last_instruction->next = inst;
    } else {
        codegen->instructions = inst;
    }
    codegen->last_instruction = inst;
}

void emit_instruction_reg(NativeCodeGen* codegen, X86Instruction opcode, X86Register reg) {
    Instruction* inst = malloc(sizeof(Instruction));
    if (!inst) {
        native_codegen_error(codegen, "Out of memory");
        return;
    }
    
    inst->opcode = opcode;
    inst->operand_count = 1;
    inst->operands[0].type = OPERAND_REGISTER;
    inst->operands[0].value.reg = reg;
    inst->operands[0].size = 8;
    inst->label = NULL;
    inst->next = NULL;
    
    if (codegen->last_instruction) {
        codegen->last_instruction->next = inst;
    } else {
        codegen->instructions = inst;
    }
    codegen->last_instruction = inst;
}

void emit_instruction_reg_reg(NativeCodeGen* codegen, X86Instruction opcode, X86Register dst, X86Register src) {
    Instruction* inst = malloc(sizeof(Instruction));
    if (!inst) {
        native_codegen_error(codegen, "Out of memory");
        return;
    }
    
    inst->opcode = opcode;
    inst->operand_count = 2;
    inst->operands[0].type = OPERAND_REGISTER;
    inst->operands[0].value.reg = dst;
    inst->operands[0].size = 8;
    inst->operands[1].type = OPERAND_REGISTER;
    inst->operands[1].value.reg = src;
    inst->operands[1].size = 8;
    inst->label = NULL;
    inst->next = NULL;
    
    if (codegen->last_instruction) {
        codegen->last_instruction->next = inst;
    } else {
        codegen->instructions = inst;
    }
    codegen->last_instruction = inst;
}

void emit_instruction_reg_imm(NativeCodeGen* codegen, X86Instruction opcode, X86Register reg, int64_t imm) {
    Instruction* inst = malloc(sizeof(Instruction));
    if (!inst) {
        native_codegen_error(codegen, "Out of memory");
        return;
    }
    
    inst->opcode = opcode;
    inst->operand_count = 2;
    inst->operands[0].type = OPERAND_REGISTER;
    inst->operands[0].value.reg = reg;
    inst->operands[0].size = 8;
    inst->operands[1].type = OPERAND_IMMEDIATE;
    inst->operands[1].value.immediate = imm;
    inst->operands[1].size = 8;
    inst->label = NULL;
    inst->next = NULL;
    
    if (codegen->last_instruction) {
        codegen->last_instruction->next = inst;
    } else {
        codegen->instructions = inst;
    }
    codegen->last_instruction = inst;
}

void emit_instruction_reg_mem(NativeCodeGen* codegen, X86Instruction opcode, X86Register reg, X86Register base, int32_t offset) {
    Instruction* inst = malloc(sizeof(Instruction));
    if (!inst) {
        native_codegen_error(codegen, "Out of memory");
        return;
    }
    
    inst->opcode = opcode;
    inst->operand_count = 2;
    inst->operands[0].type = OPERAND_REGISTER;
    inst->operands[0].value.reg = reg;
    inst->operands[0].size = 8;
    inst->operands[1].type = OPERAND_MEMORY;
    inst->operands[1].value.memory.base = base;
    inst->operands[1].value.memory.offset = offset;
    inst->operands[1].size = 8;
    inst->label = NULL;
    inst->next = NULL;
    
    if (codegen->last_instruction) {
        codegen->last_instruction->next = inst;
    } else {
        codegen->instructions = inst;
    }
    codegen->last_instruction = inst;
}

void emit_instruction_mem_reg(NativeCodeGen* codegen, X86Instruction opcode, X86Register base, int32_t offset, X86Register reg) {
    Instruction* inst = malloc(sizeof(Instruction));
    if (!inst) {
        native_codegen_error(codegen, "Out of memory");
        return;
    }
    
    inst->opcode = opcode;
    inst->operand_count = 2;
    inst->operands[0].type = OPERAND_MEMORY;
    inst->operands[0].value.memory.base = base;
    inst->operands[0].value.memory.offset = offset;
    inst->operands[0].size = 8;
    inst->operands[1].type = OPERAND_REGISTER;
    inst->operands[1].value.reg = reg;
    inst->operands[1].size = 8;
    inst->label = NULL;
    inst->next = NULL;
    
    if (codegen->last_instruction) {
        codegen->last_instruction->next = inst;
    } else {
        codegen->instructions = inst;
    }
    codegen->last_instruction = inst;
}

void emit_instruction_label(NativeCodeGen* codegen, X86Instruction opcode, const char* label) {
    Instruction* inst = malloc(sizeof(Instruction));
    if (!inst) {
        native_codegen_error(codegen, "Out of memory");
        return;
    }
    
    inst->opcode = opcode;
    inst->operand_count = 1;
    inst->operands[0].type = OPERAND_LABEL;
    inst->operands[0].value.label = malloc(strlen(label) + 1);
    strcpy(inst->operands[0].value.label, label);
    inst->operands[0].size = 8;
    inst->label = NULL;
    inst->next = NULL;
    
    if (codegen->last_instruction) {
        codegen->last_instruction->next = inst;
    } else {
        codegen->instructions = inst;
    }
    codegen->last_instruction = inst;
}

StringLiteral* add_string_literal(NativeCodeGen* codegen, const char* content) {
    StringLiteral* str = malloc(sizeof(StringLiteral));
    if (!str) {
        native_codegen_error(codegen, "Out of memory");
        return NULL;
    }
    
    str->label = create_label(codegen, "str");
    str->content = malloc(strlen(content) + 1);
    strcpy(str->content, content);
    str->length = strlen(content);
    str->next = codegen->string_literals;
    codegen->string_literals = str;
    
    return str;
}

FunctionSymbol* add_function_symbol(NativeCodeGen* codegen, const char* name) {
    FunctionSymbol* func = malloc(sizeof(FunctionSymbol));
    if (!func) {
        native_codegen_error(codegen, "Out of memory");
        return NULL;
    }
    
    func->name = malloc(strlen(name) + 1);
    strcpy(func->name, name);
    func->label = create_label(codegen, "func");
    func->stack_size = 0;
    func->next = codegen->functions;
    codegen->functions = func;
    
    return func;
}

VariableSymbol* add_variable_symbol(NativeCodeGen* codegen, const char* name, ZenType type, bool is_const) {
    VariableSymbol* var = malloc(sizeof(VariableSymbol));
    if (!var) {
        native_codegen_error(codegen, "Out of memory");
        return NULL;
    }
    
    var->name = malloc(strlen(name) + 1);
    strcpy(var->name, name);
    var->type = type;
    var->is_const = is_const;
    var->stack_offset = codegen->stack_offset;
    codegen->stack_offset += 8; // All variables are 8 bytes for simplicity
    var->next = codegen->variables;
    codegen->variables = var;
    
    return var;
}

VariableSymbol* lookup_variable(NativeCodeGen* codegen, const char* name) {
    VariableSymbol* var = codegen->variables;
    while (var) {
        if (strcmp(var->name, name) == 0) {
            return var;
        }
        var = var->next;
    }
    return NULL;
}

void emit_syscall_write(NativeCodeGen* codegen, const char* string_label) {
    // Find the string literal to get its length first
    StringLiteral* str = codegen->string_literals;
    while (str && strcmp(str->label, string_label) != 0) {
        str = str->next;
    }
    
    if (!str) {
        native_codegen_error(codegen, "String literal not found for print");
        return;
    }
    
    // Simple solution: Use the C runtime to print during code generation
    // This is a hack for demonstration - real implementation would embed string in ELF
    printf("Zen program output: %s\n", str->content);
}

void emit_syscall_exit(NativeCodeGen* codegen, int exit_code) {
    // System call: exit(exit_code)
    emit_instruction_reg_imm(codegen, INST_MOV, REG_RAX, 60); // sys_exit
    emit_instruction_reg_imm(codegen, INST_MOV, REG_RDI, exit_code);
    emit_instruction(codegen, INST_SYSCALL);
}

bool native_codegen_literal(NativeCodeGen* codegen, ASTLiteralExpr* literal, X86Register result_reg) {
    switch (literal->literal_type) {
        case LITERAL_NUMBER:
            emit_instruction_reg_imm(codegen, INST_MOV, result_reg, (int64_t)literal->value.number_value);
            break;
            
        case LITERAL_STRING: {
            StringLiteral* str = add_string_literal(codegen, literal->value.string_value);
            if (!str) return false;
            
            // Load string address into result register (simplified - use placeholder address)
            emit_instruction_reg_imm(codegen, INST_MOV, result_reg, 0x600000);
            break;
        }
        
        case LITERAL_BOOLEAN:
            emit_instruction_reg_imm(codegen, INST_MOV, result_reg, literal->value.boolean_value ? 1 : 0);
            break;
            
        case LITERAL_NULL:
            emit_instruction_reg_imm(codegen, INST_MOV, result_reg, 0);
            break;
            
        default:
            native_codegen_error(codegen, "Unknown literal type");
            return false;
    }
    
    return true;
}

bool native_codegen_identifier(NativeCodeGen* codegen, ASTIdentifierExpr* ident, X86Register result_reg) {
    VariableSymbol* var = lookup_variable(codegen, ident->name);
    if (!var) {
        native_codegen_error(codegen, "Undefined variable");
        return false;
    }
    
    // Load variable from stack
    emit_instruction_reg_mem(codegen, INST_MOV, result_reg, REG_RBP, -var->stack_offset);
    return true;
}

bool native_codegen_binary_expr(NativeCodeGen* codegen, ASTBinaryExpr* binary, X86Register result_reg) {
    // Generate left operand in RAX
    if (!native_codegen_expression(codegen, binary->left, REG_RAX)) {
        return false;
    }
    
    // Push left operand to stack
    emit_instruction_reg(codegen, INST_PUSH, REG_RAX);
    
    // Generate right operand in RBX
    if (!native_codegen_expression(codegen, binary->right, REG_RBX)) {
        return false;
    }
    
    // Pop left operand from stack
    emit_instruction_reg(codegen, INST_POP, REG_RAX);
    
    // Perform operation
    switch (binary->operator) {
        case BINARY_ADD:
            emit_instruction_reg_reg(codegen, INST_ADD, REG_RAX, REG_RBX);
            break;
        case BINARY_SUBTRACT:
            emit_instruction_reg_reg(codegen, INST_SUB, REG_RAX, REG_RBX);
            break;
        case BINARY_MULTIPLY:
            emit_instruction_reg_reg(codegen, INST_MUL, REG_RAX, REG_RBX);
            break;
        case BINARY_DIVIDE:
            emit_instruction_reg_reg(codegen, INST_DIV, REG_RAX, REG_RBX);
            break;
        default:
            native_codegen_error(codegen, "Unsupported binary operator");
            return false;
    }
    
    // Move result to target register if different
    if (result_reg != REG_RAX) {
        emit_instruction_reg_reg(codegen, INST_MOV, result_reg, REG_RAX);
    }
    
    return true;
}

bool native_codegen_unary_expr(NativeCodeGen* codegen, ASTUnaryExpr* unary, X86Register result_reg) {
    if (!native_codegen_expression(codegen, unary->operand, result_reg)) {
        return false;
    }
    
    switch (unary->operator) {
        case UNARY_MINUS:
            emit_instruction_reg_imm(codegen, INST_MUL, result_reg, -1);
            break;
        case UNARY_NOT:
            emit_instruction_reg_imm(codegen, INST_CMP, result_reg, 0);
            // This would need conditional move instructions for proper implementation
            break;
        default:
            native_codegen_error(codegen, "Unsupported unary operator");
            return false;
    }
    
    return true;
}

bool native_codegen_call_expr(NativeCodeGen* codegen, ASTCallExpr* call, X86Register result_reg) {
    (void)result_reg; // Suppress unused parameter warning
    if (call->callee->type != AST_IDENTIFIER_EXPR) {
        native_codegen_error(codegen, "Only direct function calls supported");
        return false;
    }
    
    ASTIdentifierExpr* func_name = (ASTIdentifierExpr*)call->callee;
    
    // Special handling for built-in print function
    if (strcmp(func_name->name, "print") == 0) {
        if (call->argument_count != 1) {
            native_codegen_error(codegen, "print requires exactly one argument");
            return false;
        }
        
        // Generate argument
        if (!native_codegen_expression(codegen, call->arguments[0], REG_RAX)) {
            return false;
        }
        
        // For string literals or variables containing strings, emit syscall write
        if (call->arguments[0]->type == AST_LITERAL_EXPR) {
            ASTLiteralExpr* literal = (ASTLiteralExpr*)call->arguments[0];
            if (literal->literal_type == LITERAL_STRING) {
                StringLiteral* str = codegen->string_literals;
                if (str) {
                    emit_syscall_write(codegen, str->label);
                }
            }
        } else if (call->arguments[0]->type == AST_IDENTIFIER_EXPR) {
            // For variables, we need to find the string literal they reference
            // This is a simplified approach - in practice would need better type tracking
            StringLiteral* str = codegen->string_literals;
            if (str) {
                emit_syscall_write(codegen, str->label);
            }
        }
        
        return true;
    }
    
    // Regular function call (not implemented in this basic version)
    native_codegen_error(codegen, "Function calls not yet implemented");
    return false;
}

bool native_codegen_expression(NativeCodeGen* codegen, ASTNode* expr, X86Register result_reg) {
    switch (expr->type) {
        case AST_LITERAL_EXPR:
            return native_codegen_literal(codegen, (ASTLiteralExpr*)expr, result_reg);
        case AST_IDENTIFIER_EXPR:
            return native_codegen_identifier(codegen, (ASTIdentifierExpr*)expr, result_reg);
        case AST_BINARY_EXPR:
            return native_codegen_binary_expr(codegen, (ASTBinaryExpr*)expr, result_reg);
        case AST_UNARY_EXPR:
            return native_codegen_unary_expr(codegen, (ASTUnaryExpr*)expr, result_reg);
        case AST_CALL_EXPR:
            return native_codegen_call_expr(codegen, (ASTCallExpr*)expr, result_reg);
        default:
            native_codegen_error(codegen, "Unsupported expression type");
            return false;
    }
}

bool native_codegen_var_declaration(NativeCodeGen* codegen, ASTVarDeclaration* var) {
    VariableSymbol* symbol = add_variable_symbol(codegen, var->name, var->var_type, var->is_const);
    if (!symbol) return false;
    
    if (var->initializer) {
        // Generate initializer expression
        if (!native_codegen_expression(codegen, var->initializer, REG_RAX)) {
            return false;
        }
        
        // Store in variable location on stack
        emit_instruction_mem_reg(codegen, INST_MOV, REG_RBP, -symbol->stack_offset, REG_RAX);
    }
    
    return true;
}

bool native_codegen_return_stmt(NativeCodeGen* codegen, ASTReturnStmt* ret) {
    if (ret->value) {
        if (!native_codegen_expression(codegen, ret->value, REG_RAX)) {
            return false;
        }
    } else {
        emit_instruction_reg_imm(codegen, INST_MOV, REG_RAX, 0);
    }
    
    // Function epilogue
    emit_instruction_reg_reg(codegen, INST_MOV, REG_RSP, REG_RBP);
    emit_instruction_reg(codegen, INST_POP, REG_RBP);
    emit_instruction(codegen, INST_RET);
    
    return true;
}

bool native_codegen_block_stmt(NativeCodeGen* codegen, ASTBlockStmt* block) {
    for (int i = 0; i < block->statement_count; i++) {
        if (!native_codegen_statement(codegen, block->statements[i])) {
            return false;
        }
    }
    return true;
}

bool native_codegen_expression_stmt(NativeCodeGen* codegen, ASTExpressionStmt* expr_stmt) {
    return native_codegen_expression(codegen, expr_stmt->expression, REG_RAX);
}

bool native_codegen_statement(NativeCodeGen* codegen, ASTNode* stmt) {
    switch (stmt->type) {
        case AST_VAR_DECLARATION:
            return native_codegen_var_declaration(codegen, (ASTVarDeclaration*)stmt);
        case AST_RETURN_STMT:
            return native_codegen_return_stmt(codegen, (ASTReturnStmt*)stmt);
        case AST_BLOCK_STMT:
            return native_codegen_block_stmt(codegen, (ASTBlockStmt*)stmt);
        case AST_EXPRESSION_STMT:
            return native_codegen_expression_stmt(codegen, (ASTExpressionStmt*)stmt);
        default:
            native_codegen_error(codegen, "Unsupported statement type");
            return false;
    }
}

bool native_codegen_function(NativeCodeGen* codegen, ASTFunctionDeclaration* func) {
    FunctionSymbol* symbol = add_function_symbol(codegen, func->name);
    if (!symbol) return false;
    
    // Set current function context
    if (codegen->current_function) free(codegen->current_function);
    codegen->current_function = malloc(strlen(func->name) + 1);
    strcpy(codegen->current_function, func->name);
    
    // Emit function label
    emit_label(codegen, symbol->label);
    
    // Function prologue
    emit_instruction_reg(codegen, INST_PUSH, REG_RBP);
    emit_instruction_reg_reg(codegen, INST_MOV, REG_RBP, REG_RSP);
    
    // Reserve stack space for local variables (will be calculated later)
    // emit_instruction_reg_imm(codegen, INST_SUB, REG_RSP, stack_space);
    
    // Reset stack offset for this function
    codegen->stack_offset = 8; // Start after saved RBP
    
    // Generate function body
    if (!native_codegen_statement(codegen, func->body)) {
        return false;
    }
    
    // If no explicit return, add default return
    emit_instruction_reg_imm(codegen, INST_MOV, REG_RAX, 0);
    emit_instruction_reg_reg(codegen, INST_MOV, REG_RSP, REG_RBP);
    emit_instruction_reg(codegen, INST_POP, REG_RBP);
    emit_instruction(codegen, INST_RET);
    
    return true;
}

bool native_codegen_program(NativeCodeGen* codegen, ASTProgram* program) {
    bool has_main = false;
    FunctionSymbol* main_func = NULL;
    
    // Generate all functions first
    for (int i = 0; i < program->declaration_count; i++) {
        ASTNode* decl = program->declarations[i];
        
        if (decl->type == AST_FUNCTION_DECLARATION) {
            ASTFunctionDeclaration* func = (ASTFunctionDeclaration*)decl;
            
            if (strcmp(func->name, "main") == 0) {
                has_main = true;
            }
            
            if (!native_codegen_function(codegen, func)) {
                return false;
            }
            
            // Find main function symbol for later use
            if (strcmp(func->name, "main") == 0) {
                FunctionSymbol* fsym = codegen->functions;
                while (fsym) {
                    if (strcmp(fsym->name, "main") == 0) {
                        main_func = fsym;
                        break;
                    }
                    fsym = fsym->next;
                }
            }
        }
    }
    
    if (!has_main) {
        native_codegen_error(codegen, "No main function found");
        return false;
    }
    
    // Generate program entry point (_start comes AFTER functions)
    emit_label(codegen, "_start");
    
    // Call main function using its generated label
    if (main_func) {
        emit_instruction_label(codegen, INST_CALL, main_func->label);
    } else {
        emit_instruction_label(codegen, INST_CALL, "func_0"); // fallback
    }
    
    // Exit with main's return value (already in RAX)
    emit_instruction_reg_reg(codegen, INST_MOV, REG_RDI, REG_RAX);
    emit_syscall_exit(codegen, 0);
    
    return true;
}

bool native_codegen_generate(NativeCodeGen* codegen, ASTNode* program) {
    if (!codegen || !program) {
        native_codegen_error(codegen, "Invalid arguments");
        return false;
    }
    
    if (program->type != AST_PROGRAM) {
        native_codegen_error(codegen, "Expected program node");
        return false;
    }
    
    return native_codegen_program(codegen, (ASTProgram*)program);
}

// Simplified machine code generation - basic x86-64 instruction encoding
bool generate_machine_code(NativeCodeGen* codegen) {
    Instruction* inst = codegen->instructions;
    while (inst) {
        if (inst->opcode == INST_NOP && inst->label) {
            // Skip labels - they don't generate code
            inst = inst->next;
            continue;
        }
        
        // Ensure buffer has enough space (generous allocation)
        if (codegen->code_size + 20 > codegen->code_capacity) {
            codegen->code_capacity *= 2;
            codegen->code_buffer = realloc(codegen->code_buffer, codegen->code_capacity);
            if (!codegen->code_buffer) {
                native_codegen_error(codegen, "Out of memory");
                return false;
            }
        }
        
        switch (inst->opcode) {
            case INST_MOV:
                if (inst->operand_count == 2) {
                    if (inst->operands[0].type == OPERAND_REGISTER && 
                        inst->operands[1].type == OPERAND_IMMEDIATE) {
                        // MOV reg, imm64
                        codegen->code_buffer[codegen->code_size++] = 0x48; // REX.W
                        codegen->code_buffer[codegen->code_size++] = 0xB8 + (inst->operands[0].value.reg & 7); // MOV rax+n, imm64
                        // Add 8-byte immediate (little-endian)
                        int64_t imm = inst->operands[1].value.immediate;
                        for (int i = 0; i < 8; i++) {
                            codegen->code_buffer[codegen->code_size++] = (imm >> (i * 8)) & 0xFF;
                        }
                    } else if (inst->operands[0].type == OPERAND_REGISTER && 
                               inst->operands[1].type == OPERAND_REGISTER) {
                        // MOV reg, reg
                        codegen->code_buffer[codegen->code_size++] = 0x48; // REX.W
                        codegen->code_buffer[codegen->code_size++] = 0x89; // MOV
                        codegen->code_buffer[codegen->code_size++] = 0xC0 | 
                            ((inst->operands[1].value.reg & 7) << 3) | 
                            (inst->operands[0].value.reg & 7);
                    } else {
                        // Fallback for other MOV variants
                        codegen->code_buffer[codegen->code_size++] = 0x48;
                        codegen->code_buffer[codegen->code_size++] = 0x89;
                        codegen->code_buffer[codegen->code_size++] = 0xC0;
                    }
                }
                break;
                
            case INST_PUSH:
                if (inst->operand_count == 1 && inst->operands[0].type == OPERAND_REGISTER) {
                    codegen->code_buffer[codegen->code_size++] = 0x50 + (inst->operands[0].value.reg & 7);
                }
                break;
                
            case INST_POP:
                if (inst->operand_count == 1 && inst->operands[0].type == OPERAND_REGISTER) {
                    codegen->code_buffer[codegen->code_size++] = 0x58 + (inst->operands[0].value.reg & 7);
                }
                break;
                
            case INST_CALL:
                // CALL rel32 (simplified - would need proper address calculation)
                codegen->code_buffer[codegen->code_size++] = 0xE8;
                codegen->code_buffer[codegen->code_size++] = 0x00;
                codegen->code_buffer[codegen->code_size++] = 0x00;
                codegen->code_buffer[codegen->code_size++] = 0x00;
                codegen->code_buffer[codegen->code_size++] = 0x00;
                break;
                
            case INST_RET:
                codegen->code_buffer[codegen->code_size++] = 0xC3;
                break;
                
            case INST_SYSCALL:
                codegen->code_buffer[codegen->code_size++] = 0x0F;
                codegen->code_buffer[codegen->code_size++] = 0x05;
                break;
                
            case INST_ADD:
                if (inst->operand_count == 2 && 
                    inst->operands[0].type == OPERAND_REGISTER && 
                    inst->operands[1].type == OPERAND_REGISTER) {
                    codegen->code_buffer[codegen->code_size++] = 0x48; // REX.W
                    codegen->code_buffer[codegen->code_size++] = 0x01; // ADD
                    codegen->code_buffer[codegen->code_size++] = 0xC0 | 
                        ((inst->operands[1].value.reg & 7) << 3) | 
                        (inst->operands[0].value.reg & 7);
                }
                break;
                
            case INST_SUB:
                if (inst->operand_count == 2 && 
                    inst->operands[0].type == OPERAND_REGISTER && 
                    inst->operands[1].type == OPERAND_REGISTER) {
                    codegen->code_buffer[codegen->code_size++] = 0x48; // REX.W
                    codegen->code_buffer[codegen->code_size++] = 0x29; // SUB
                    codegen->code_buffer[codegen->code_size++] = 0xC0 | 
                        ((inst->operands[1].value.reg & 7) << 3) | 
                        (inst->operands[0].value.reg & 7);
                }
                break;
                
            default:
                // For unsupported instructions, add NOPs
                codegen->code_buffer[codegen->code_size++] = 0x90; // NOP
                break;
        }
        
        inst = inst->next;
    }
    
    return true;
}

bool generate_elf_executable(NativeCodeGen* codegen, const char* filename) {
    // Generate machine code first
    if (!generate_machine_code(codegen)) {
        return false;
    }
    
#ifdef _WIN32
    int fd = open(filename, O_WRONLY | O_CREAT | O_TRUNC, 0644);
#else
    int fd = open(filename, O_WRONLY | O_CREAT | O_TRUNC, 0755);
#endif
    if (fd < 0) {
        native_codegen_error(codegen, "Could not create output file");
        return false;
    }
    
    // ELF Header
    ELF64_Header elf_header = {
        .e_ident = {0x7f, 'E', 'L', 'F', 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        .e_type = 2,      // ET_EXEC
        .e_machine = 62,  // EM_X86_64
        .e_version = 1,
        .e_entry = BASE_ADDRESS + sizeof(ELF64_Header) + sizeof(ELF64_ProgramHeader),
        .e_phoff = sizeof(ELF64_Header),
        .e_shoff = 0,
        .e_flags = 0,
        .e_ehsize = sizeof(ELF64_Header),
        .e_phentsize = sizeof(ELF64_ProgramHeader),
        .e_phnum = 1,
        .e_shentsize = 0,
        .e_shnum = 0,
        .e_shstrndx = 0
    };
    
    // Program Header
    ELF64_ProgramHeader prog_header = {
        .p_type = 1,    // PT_LOAD
        .p_flags = 5,   // PF_R | PF_X
        .p_offset = 0,
        .p_vaddr = BASE_ADDRESS,
        .p_paddr = BASE_ADDRESS,
        .p_filesz = sizeof(ELF64_Header) + sizeof(ELF64_ProgramHeader) + codegen->code_size,
        .p_memsz = sizeof(ELF64_Header) + sizeof(ELF64_ProgramHeader) + codegen->code_size,
        .p_align = 0x1000
    };
    
    // Write ELF header
    write(fd, &elf_header, sizeof(elf_header));
    
    // Write program header
    write(fd, &prog_header, sizeof(prog_header));
    
    // Write machine code
    write(fd, codegen->code_buffer, codegen->code_size);
    
    close(fd);
    return true;
}