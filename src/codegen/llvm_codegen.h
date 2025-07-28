#pragma once

#include <memory>
#include <string>
#include <map>
#include <vector>

#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"
#include "llvm/IR/Verifier.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/ExecutionEngine/ExecutionEngine.h"
#include "llvm/ExecutionEngine/MCJIT.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/Transforms/InstCombine/InstCombine.h"
#include "llvm/Transforms/Scalar.h"
#include "llvm/Transforms/Scalar/GVN.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/Host.h"
#include "llvm/Target/TargetOptions.h"

#include "../ast/ast_node.h"

namespace zen {

class LLVMCodeGenerator {
private:
    std::unique_ptr<llvm::LLVMContext> context;
    std::unique_ptr<llvm::Module> module;
    std::unique_ptr<llvm::IRBuilder<>> builder;
    std::unique_ptr<llvm::TargetMachine> target_machine;
    
    // Symbol tables
    std::map<std::string, llvm::Value*> named_values;
    std::map<std::string, llvm::Function*> functions;
    
    // Type mappings
    std::map<std::string, llvm::Type*> type_map;
    
    // Current function being generated
    llvm::Function* current_function;
    
public:
    LLVMCodeGenerator(const std::string& module_name);
    ~LLVMCodeGenerator() = default;
    
    // Main compilation interface
    bool generateProgram(ProgramNode* ast);
    bool emitObjectFile(const std::string& filename);
    bool linkExecutable(const std::string& output_file, const std::string& object_file);
    
    // Code generation methods
    llvm::Function* generateFunction(FunctionDeclarationNode* func);
    llvm::Value* generateExpression(ASTNode* expr);
    llvm::Value* generateStatement(ASTNode* stmt);
    
    // Type system
    llvm::Type* getZenType(const std::string& type_name);
    llvm::Type* getLLVMType(const std::string& zen_type);
    
    // Utility methods
    void initializeModule();
    void setupTargetMachine();
    bool verifyModule();
    void dumpModule();
    
private:
    // Expression generators
    llvm::Value* generateLiteral(LiteralNode* literal);
    llvm::Value* generateIdentifier(IdentifierNode* identifier);
    llvm::Value* generateBinaryOp(BinaryOpNode* binary_op);
    llvm::Value* generateUnaryOp(UnaryOpNode* unary_op);
    llvm::Value* generateAssignment(AssignmentNode* assignment);
    llvm::Value* generateFunctionCall(FunctionCallNode* func_call);
    
    // Statement generators
    llvm::Value* generateVariableDeclaration(VariableDeclarationNode* var_decl);
    llvm::Value* generateReturnStatement(ReturnStatementNode* return_stmt);
    llvm::Value* generateBlockStatement(BlockStatementNode* block);
    llvm::Value* generateIfStatement(IfStatementNode* if_stmt);
    llvm::Value* generateExpressionStatement(ExpressionStmtNode* expr_stmt);
    
    // Helper methods
    llvm::Value* createEntryBlockAlloca(llvm::Function* function, const std::string& var_name, llvm::Type* type);
    void createBuiltinFunctions();
    
    // Error handling
    void logError(const std::string& message);
    bool hasError;
    std::string error_message;
};

} // namespace zen