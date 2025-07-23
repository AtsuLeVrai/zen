#ifndef ZEN_NATIVE_CODEGEN_H
#define ZEN_NATIVE_CODEGEN_H

#include "ast.h"
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

// x86-64 Registers
typedef enum {
    REG_RAX = 0, REG_RCX = 1, REG_RDX = 2, REG_RBX = 3,
    REG_RSP = 4, REG_RBP = 5, REG_RSI = 6, REG_RDI = 7,
    REG_R8  = 8, REG_R9  = 9, REG_R10 = 10, REG_R11 = 11,
    REG_R12 = 12, REG_R13 = 13, REG_R14 = 14, REG_R15 = 15
} X86Register;

// x86-64 Instructions
typedef enum {
    INST_MOV, INST_PUSH, INST_POP, INST_ADD, INST_SUB, INST_MUL, INST_DIV,
    INST_CMP, INST_JMP, INST_JE, INST_JNE, INST_JL, INST_JLE, INST_JG, INST_JGE,
    INST_CALL, INST_RET, INST_NOP, INST_SYSCALL, INST_XOR, INST_LEA, INST_INT3,
    INST_SETE, INST_SETNE, INST_SETL, INST_SETLE, INST_SETG, INST_SETGE, INST_MOVZX
} X86Instruction;

// Operand types
typedef enum {
    OPERAND_REGISTER,
    OPERAND_IMMEDIATE,
    OPERAND_MEMORY,
    OPERAND_LABEL
} OperandType;

// Operand structure
typedef struct {
    OperandType type;
    union {
        X86Register reg;
        int64_t immediate;
        struct {
            X86Register base;
            int32_t offset;
        } memory;
        char* label;
    } value;
    int size; // 1, 2, 4, or 8 bytes
} Operand;

// Machine code instruction
typedef struct Instruction {
    X86Instruction opcode;
    Operand operands[2]; // Most x86 instructions have at most 2 operands
    int operand_count;
    char* label; // Optional label for this instruction
    struct Instruction* next;
} Instruction;

// String literal entry
typedef struct StringLiteral {
    char* label;
    char* content;
    size_t length;
    struct StringLiteral* next;
} StringLiteral;

// Function symbol
typedef struct FunctionSymbol {
    char* name;
    char* label;
    int stack_size;
    struct FunctionSymbol* next;
} FunctionSymbol;

// Variable symbol
typedef struct VariableSymbol {
    char* name;
    ZenType type;
    bool is_const;
    int stack_offset; // Offset from RBP
    struct VariableSymbol* next;
} VariableSymbol;

// Native code generator context
typedef struct {
    Instruction* instructions;
    Instruction* last_instruction;
    StringLiteral* string_literals;
    FunctionSymbol* functions;
    VariableSymbol* variables;
    
    // Current function context
    char* current_function;
    int stack_offset;
    int label_counter;
    
    // Code buffer for binary output
    uint8_t* code_buffer;
    size_t code_size;
    size_t code_capacity;
    
    // Error handling
    bool had_error;
    char* error_message;
} NativeCodeGen;

// ELF file structures
typedef struct {
    uint8_t e_ident[16];
    uint16_t e_type;
    uint16_t e_machine;
    uint32_t e_version;
    uint64_t e_entry;
    uint64_t e_phoff;
    uint64_t e_shoff;
    uint32_t e_flags;
    uint16_t e_ehsize;
    uint16_t e_phentsize;
    uint16_t e_phnum;
    uint16_t e_shentsize;
    uint16_t e_shnum;
    uint16_t e_shstrndx;
} __attribute__((packed)) ELF64_Header;

typedef struct {
    uint32_t p_type;
    uint32_t p_flags;
    uint64_t p_offset;
    uint64_t p_vaddr;
    uint64_t p_paddr;
    uint64_t p_filesz;
    uint64_t p_memsz;
    uint64_t p_align;
} __attribute__((packed)) ELF64_ProgramHeader;

// Function declarations
NativeCodeGen* native_codegen_create(void);
void native_codegen_destroy(NativeCodeGen* codegen);

// Main generation functions
bool native_codegen_generate(NativeCodeGen* codegen, ASTNode* program);
bool native_codegen_program(NativeCodeGen* codegen, ASTProgram* program);
bool native_codegen_function(NativeCodeGen* codegen, ASTFunctionDeclaration* func);
bool native_codegen_statement(NativeCodeGen* codegen, ASTNode* stmt);
bool native_codegen_expression(NativeCodeGen* codegen, ASTNode* expr, X86Register result_reg);

// Expression generation
bool native_codegen_literal(NativeCodeGen* codegen, ASTLiteralExpr* literal, X86Register result_reg);
bool native_codegen_identifier(NativeCodeGen* codegen, ASTIdentifierExpr* ident, X86Register result_reg);
bool native_codegen_binary_expr(NativeCodeGen* codegen, ASTBinaryExpr* binary, X86Register result_reg);
bool native_codegen_unary_expr(NativeCodeGen* codegen, ASTUnaryExpr* unary, X86Register result_reg);
bool native_codegen_call_expr(NativeCodeGen* codegen, ASTCallExpr* call, X86Register result_reg);

// Statement generation
bool native_codegen_var_declaration(NativeCodeGen* codegen, ASTVarDeclaration* var);
bool native_codegen_return_stmt(NativeCodeGen* codegen, ASTReturnStmt* ret);
bool native_codegen_block_stmt(NativeCodeGen* codegen, ASTBlockStmt* block);
bool native_codegen_expression_stmt(NativeCodeGen* codegen, ASTExpressionStmt* expr_stmt);
bool native_codegen_if_stmt(NativeCodeGen* codegen, ASTIfStmt* if_stmt);

// Instruction emission
void emit_instruction(NativeCodeGen* codegen, X86Instruction opcode);
void emit_instruction_reg(NativeCodeGen* codegen, X86Instruction opcode, X86Register reg);
void emit_instruction_reg_reg(NativeCodeGen* codegen, X86Instruction opcode, X86Register dst, X86Register src);
void emit_instruction_reg_imm(NativeCodeGen* codegen, X86Instruction opcode, X86Register reg, int64_t imm);
void emit_instruction_reg_mem(NativeCodeGen* codegen, X86Instruction opcode, X86Register reg, X86Register base, int32_t offset);
void emit_instruction_mem_reg(NativeCodeGen* codegen, X86Instruction opcode, X86Register base, int32_t offset, X86Register reg);
void emit_instruction_label(NativeCodeGen* codegen, X86Instruction opcode, const char* label);

// Label management
char* create_label(NativeCodeGen* codegen, const char* prefix);
void emit_label(NativeCodeGen* codegen, const char* label);

// Symbol management
StringLiteral* add_string_literal(NativeCodeGen* codegen, const char* content);
FunctionSymbol* add_function_symbol(NativeCodeGen* codegen, const char* name);
VariableSymbol* add_variable_symbol(NativeCodeGen* codegen, const char* name, ZenType type, bool is_const);
VariableSymbol* lookup_variable(NativeCodeGen* codegen, const char* name);

// Machine code generation
bool generate_machine_code(NativeCodeGen* codegen);
void encode_instruction(NativeCodeGen* codegen, Instruction* inst);

// System call helpers
void emit_syscall_write(NativeCodeGen* codegen, const char* string_label);
void emit_syscall_exit(NativeCodeGen* codegen, int exit_code);

// ELF file generation
bool generate_elf_executable(NativeCodeGen* codegen, const char* filename);

// Utility functions
const char* register_name(X86Register reg);
int register_encoding(X86Register reg);
bool is_register_extended(X86Register reg);

// Error handling
void native_codegen_error(NativeCodeGen* codegen, const char* message);

#endif // ZEN_NATIVE_CODEGEN_H