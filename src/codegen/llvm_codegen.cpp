#include "llvm_codegen.h"
#include "../lexer/token.h"
#include <iostream>

namespace zen {

LLVMCodeGenerator::LLVMCodeGenerator(const std::string& module_name) 
    : hasError(false), current_function(nullptr) {
    context = std::make_unique<llvm::LLVMContext>();
    module = std::make_unique<llvm::Module>(module_name, *context);
    builder = std::make_unique<llvm::IRBuilder<>>(*context);
    
    initializeModule();
    setupTargetMachine();
    createBuiltinFunctions();
}

void LLVMCodeGenerator::initializeModule() {
    // Initialize LLVM targets
    llvm::InitializeAllTargetInfos();
    llvm::InitializeAllTargets();
    llvm::InitializeAllTargetMCs();
    llvm::InitializeAllAsmParsers();
    llvm::InitializeAllAsmPrinters();
    
    // Setup type mappings
    type_map["i32"] = llvm::Type::getInt32Ty(*context);
    type_map["i64"] = llvm::Type::getInt64Ty(*context);
    type_map["f64"] = llvm::Type::getDoubleTy(*context);
    type_map["bool"] = llvm::Type::getInt1Ty(*context);
    type_map["void"] = llvm::Type::getVoidTy(*context);
    type_map["string"] = llvm::Type::getInt8PtrTy(*context);
}

void LLVMCodeGenerator::setupTargetMachine() {
    auto target_triple = llvm::sys::getDefaultTargetTriple();
    module->setTargetTriple(target_triple);
    
    std::string error;
    auto target = llvm::TargetRegistry::lookupTarget(target_triple, error);
    
    if (!target) {
        logError("Failed to lookup target: " + error);
        return;
    }
    
    auto cpu = "generic";
    auto features = "";
    
    llvm::TargetOptions opt;
    auto reloc_model = llvm::Optional<llvm::Reloc::Model>();
    target_machine = std::unique_ptr<llvm::TargetMachine>(
        target->createTargetMachine(target_triple, cpu, features, opt, reloc_model));
    
    module->setDataLayout(target_machine->createDataLayout());
}

void LLVMCodeGenerator::createBuiltinFunctions() {
    // Create printf function declaration for print functionality
    std::vector<llvm::Type*> printf_args;
    printf_args.push_back(llvm::Type::getInt8PtrTy(*context));
    
    llvm::FunctionType* printf_type = llvm::FunctionType::get(
        llvm::Type::getInt32Ty(*context), printf_args, true);
    
    llvm::Function* printf_func = llvm::Function::Create(
        printf_type, llvm::Function::ExternalLinkage, "printf", module.get());
    
    functions["printf"] = printf_func;
}

bool LLVMCodeGenerator::generateProgram(ProgramNode* ast) {
    if (hasError) return false;
    
    for (auto& decl : ast->declarations) {
        if (auto func_decl = dynamic_cast<FunctionDeclarationNode*>(decl.get())) {
            if (!generateFunction(func_decl)) {
                return false;
            }
        } else {
            // Handle other top-level declarations
            generateStatement(decl.get());
        }
    }
    
    return verifyModule();
}

llvm::Function* LLVMCodeGenerator::generateFunction(FunctionDeclarationNode* func) {
    // Get parameter types
    std::vector<llvm::Type*> param_types;
    for (const auto& param : func->parameters) {
        llvm::Type* param_type = getLLVMType(param.type_name);
        if (!param_type) {
            logError("Unknown parameter type: " + param.type_name);
            return nullptr;
        }
        param_types.push_back(param_type);
    }
    
    // Get return type
    llvm::Type* return_type = getLLVMType(func->return_type);
    if (!return_type) {
        logError("Unknown return type: " + func->return_type);
        return nullptr;
    }
    
    // Create function type
    llvm::FunctionType* func_type = llvm::FunctionType::get(return_type, param_types, false);
    
    // Create function
    llvm::Function* function = llvm::Function::Create(
        func_type, llvm::Function::ExternalLinkage, func->name, module.get());
    
    // Set parameter names
    auto param_iter = function->arg_begin();
    for (const auto& param : func->parameters) {
        param_iter->setName(param.name);
        ++param_iter;
    }
    
    // Create entry basic block
    llvm::BasicBlock* entry_block = llvm::BasicBlock::Create(*context, "entry", function);
    builder->SetInsertPoint(entry_block);
    
    // Set current function
    current_function = function;
    
    // Clear symbol table for this function scope
    named_values.clear();
    
    // Create allocas for parameters
    param_iter = function->arg_begin();
    for (const auto& param : func->parameters) {
        llvm::Value* alloca = createEntryBlockAlloca(function, param.name, param_iter->getType());
        builder->CreateStore(&*param_iter, alloca);
        named_values[param.name] = alloca;
        ++param_iter;
    }
    
    // Generate function body
    llvm::Value* return_val = generateStatement(func->body.get());
    
    // If no explicit return and void function, add return void
    if (return_type->isVoidTy() && !builder->GetInsertBlock()->getTerminator()) {
        builder->CreateRetVoid();
    }
    
    // Verify function
    if (llvm::verifyFunction(*function, &llvm::errs())) {
        logError("Function verification failed for: " + func->name);
        function->eraseFromParent();
        return nullptr;
    }
    
    functions[func->name] = function;
    current_function = nullptr;
    
    return function;
}

llvm::Value* LLVMCodeGenerator::generateExpression(ASTNode* expr) {
    if (!expr) return nullptr;
    
    switch (expr->type) {
        case ASTNodeType::LITERAL:
            return generateLiteral(static_cast<LiteralNode*>(expr));
        case ASTNodeType::IDENTIFIER:
            return generateIdentifier(static_cast<IdentifierNode*>(expr));
        case ASTNodeType::BINARY_OP:
            return generateBinaryOp(static_cast<BinaryOpNode*>(expr));
        case ASTNodeType::UNARY_OP:
            return generateUnaryOp(static_cast<UnaryOpNode*>(expr));
        case ASTNodeType::ASSIGNMENT:
            return generateAssignment(static_cast<AssignmentNode*>(expr));
        case ASTNodeType::FUNCTION_CALL:
            return generateFunctionCall(static_cast<FunctionCallNode*>(expr));
        default:
            logError("Unsupported expression type");
            return nullptr;
    }
}

llvm::Value* LLVMCodeGenerator::generateStatement(ASTNode* stmt) {
    if (!stmt) return nullptr;
    
    switch (stmt->type) {
        case ASTNodeType::VARIABLE_DECLARATION:
            return generateVariableDeclaration(static_cast<VariableDeclarationNode*>(stmt));
        case ASTNodeType::RETURN_STATEMENT:
            return generateReturnStatement(static_cast<ReturnStatementNode*>(stmt));
        case ASTNodeType::BLOCK_STATEMENT:
            return generateBlockStatement(static_cast<BlockStatementNode*>(stmt));
        case ASTNodeType::IF_STATEMENT:
            return generateIfStatement(static_cast<IfStatementNode*>(stmt));
        case ASTNodeType::EXPRESSION_STMT:
            return generateExpressionStatement(static_cast<ExpressionStmtNode*>(stmt));
        default:
            return generateExpression(stmt);
    }
}

llvm::Value* LLVMCodeGenerator::generateLiteral(LiteralNode* literal) {
    switch (literal->literal_type) {
        case TokenType::NUMBER: {
            int value = std::stoi(literal->value);
            return llvm::ConstantInt::get(*context, llvm::APInt(32, value, true));
        }
        case TokenType::BOOL: {
            bool value = (literal->value == "true");
            return llvm::ConstantInt::get(*context, llvm::APInt(1, value ? 1 : 0, false));
        }
        case TokenType::STRING: {
            // Create global string constant
            return builder->CreateGlobalStringPtr(literal->value, "str");
        }
        default:
            logError("Unsupported literal type");
            return nullptr;
    }
}

llvm::Value* LLVMCodeGenerator::generateIdentifier(IdentifierNode* identifier) {
    llvm::Value* value = named_values[identifier->name];
    if (!value) {
        logError("Unknown variable name: " + identifier->name);
        return nullptr;
    }
    
    // Load the value from the alloca
    return builder->CreateLoad(value->getType()->getPointerElementType(), value, identifier->name.c_str());
}

llvm::Value* LLVMCodeGenerator::generateBinaryOp(BinaryOpNode* binary_op) {
    llvm::Value* left = generateExpression(binary_op->left.get());
    llvm::Value* right = generateExpression(binary_op->right.get());
    
    if (!left || !right) return nullptr;
    
    switch (binary_op->operator_type) {
        case TokenType::PLUS:
            return builder->CreateAdd(left, right, "addtmp");
        case TokenType::MINUS:
            return builder->CreateSub(left, right, "subtmp");
        case TokenType::MULTIPLY:
            return builder->CreateMul(left, right, "multmp");
        case TokenType::DIVIDE:
            return builder->CreateSDiv(left, right, "divtmp");
        case TokenType::EQUAL:
            return builder->CreateICmpEQ(left, right, "cmptmp");
        case TokenType::NOT_EQUAL:
            return builder->CreateICmpNE(left, right, "cmptmp");
        case TokenType::LESS_THAN:
            return builder->CreateICmpSLT(left, right, "cmptmp");
        case TokenType::GREATER_THAN:
            return builder->CreateICmpSGT(left, right, "cmptmp");
        case TokenType::LESS_EQUAL:
            return builder->CreateICmpSLE(left, right, "cmptmp");
        case TokenType::GREATER_EQUAL:
            return builder->CreateICmpSGE(left, right, "cmptmp");
        default:
            logError("Unsupported binary operator");
            return nullptr;
    }
}

llvm::Value* LLVMCodeGenerator::generateUnaryOp(UnaryOpNode* unary_op) {
    llvm::Value* operand = generateExpression(unary_op->operand.get());
    if (!operand) return nullptr;
    
    switch (unary_op->operator_type) {
        case TokenType::MINUS:
            return builder->CreateNeg(operand, "negtmp");
        case TokenType::NOT:
            return builder->CreateNot(operand, "nottmp");
        default:
            logError("Unsupported unary operator");
            return nullptr;
    }
}

llvm::Value* LLVMCodeGenerator::generateVariableDeclaration(VariableDeclarationNode* var_decl) {
    llvm::Type* var_type = getLLVMType(var_decl->type_name);
    if (!var_type) {
        logError("Unknown type: " + var_decl->type_name);
        return nullptr;
    }
    
    // Create alloca for the variable
    llvm::Value* alloca = createEntryBlockAlloca(current_function, var_decl->name, var_type);
    
    // Initialize if there's an initializer
    if (var_decl->initializer) {
        llvm::Value* init_val = generateExpression(var_decl->initializer.get());
        if (!init_val) return nullptr;
        
        builder->CreateStore(init_val, alloca);
    }
    
    // Add to symbol table
    named_values[var_decl->name] = alloca;
    
    return alloca;
}

llvm::Value* LLVMCodeGenerator::generateReturnStatement(ReturnStatementNode* return_stmt) {
    if (return_stmt->value) {
        llvm::Value* return_val = generateExpression(return_stmt->value.get());
        if (!return_val) return nullptr;
        return builder->CreateRet(return_val);
    } else {
        return builder->CreateRetVoid();
    }
}

llvm::Value* LLVMCodeGenerator::generateBlockStatement(BlockStatementNode* block) {
    llvm::Value* last_val = nullptr;
    
    for (auto& stmt : block->statements) {
        last_val = generateStatement(stmt.get());
        if (!last_val && hasError) return nullptr;
    }
    
    return last_val;
}

llvm::Value* LLVMCodeGenerator::generateExpressionStatement(ExpressionStmtNode* expr_stmt) {
    return generateExpression(expr_stmt->expression.get());
}

llvm::Value* LLVMCodeGenerator::generateAssignment(AssignmentNode* assignment) {
    // For now, just handle simple identifier assignment
    if (auto target = dynamic_cast<IdentifierNode*>(assignment->target.get())) {
        llvm::Value* var = named_values[target->name];
        if (!var) {
            logError("Unknown variable: " + target->name);
            return nullptr;
        }
        
        llvm::Value* value = generateExpression(assignment->value.get());
        if (!value) return nullptr;
        
        builder->CreateStore(value, var);
        return value;
    }
    
    logError("Unsupported assignment target");
    return nullptr;
}

llvm::Value* LLVMCodeGenerator::generateFunctionCall(FunctionCallNode* func_call) {
    // For now, handle simple function calls by name
    if (auto func_name = dynamic_cast<IdentifierNode*>(func_call->function.get())) {
        llvm::Function* callee = functions[func_name->name];
        if (!callee) {
            logError("Unknown function: " + func_name->name);
            return nullptr;
        }
        
        // Generate arguments
        std::vector<llvm::Value*> args;
        for (auto& arg : func_call->arguments) {
            llvm::Value* arg_val = generateExpression(arg.get());
            if (!arg_val) return nullptr;
            args.push_back(arg_val);
        }
        
        // Check argument count
        if (args.size() != callee->arg_size()) {
            logError("Incorrect number of arguments for function: " + func_name->name);
            return nullptr;
        }
        
        return builder->CreateCall(callee, args, "calltmp");
    }
    
    logError("Unsupported function call");
    return nullptr;
}

llvm::Value* LLVMCodeGenerator::generateIfStatement(IfStatementNode* if_stmt) {
    llvm::Value* cond_val = generateExpression(if_stmt->condition.get());
    if (!cond_val) return nullptr;
    
    // Convert condition to bool
    cond_val = builder->CreateICmpNE(cond_val, 
        llvm::ConstantInt::get(*context, llvm::APInt(1, 0, false)), "ifcond");
    
    llvm::Function* function = builder->GetInsertBlock()->getParent();
    
    // Create blocks
    llvm::BasicBlock* then_block = llvm::BasicBlock::Create(*context, "then", function);
    llvm::BasicBlock* else_block = llvm::BasicBlock::Create(*context, "else");
    llvm::BasicBlock* merge_block = llvm::BasicBlock::Create(*context, "ifcont");
    
    // Create conditional branch
    if (if_stmt->else_branch) {
        builder->CreateCondBr(cond_val, then_block, else_block);
    } else {
        builder->CreateCondBr(cond_val, then_block, merge_block);
    }
    
    // Generate then block
    builder->SetInsertPoint(then_block);
    llvm::Value* then_val = generateStatement(if_stmt->then_branch.get());
    if (!builder->GetInsertBlock()->getTerminator()) {
        builder->CreateBr(merge_block);
    }
    then_block = builder->GetInsertBlock();
    
    // Generate else block if present
    llvm::Value* else_val = nullptr;
    if (if_stmt->else_branch) {
        function->getBasicBlockList().push_back(else_block);
        builder->SetInsertPoint(else_block);
        else_val = generateStatement(if_stmt->else_branch.get());
        if (!builder->GetInsertBlock()->getTerminator()) {
            builder->CreateBr(merge_block);
        }
        else_block = builder->GetInsertBlock();
    }
    
    // Generate merge block
    function->getBasicBlockList().push_back(merge_block);
    builder->SetInsertPoint(merge_block);
    
    return merge_block;
}

llvm::Type* LLVMCodeGenerator::getLLVMType(const std::string& zen_type) {
    auto it = type_map.find(zen_type);
    if (it != type_map.end()) {
        return it->second;
    }
    return nullptr;
}

llvm::Value* LLVMCodeGenerator::createEntryBlockAlloca(llvm::Function* function, 
                                                       const std::string& var_name, 
                                                       llvm::Type* type) {
    llvm::IRBuilder<> tmp_builder(&function->getEntryBlock(), 
                                  function->getEntryBlock().begin());
    return tmp_builder.CreateAlloca(type, nullptr, var_name.c_str());
}

bool LLVMCodeGenerator::verifyModule() {
    std::string error_str;
    llvm::raw_string_ostream error_stream(error_str);
    
    if (llvm::verifyModule(*module, &error_stream)) {
        logError("Module verification failed: " + error_str);
        return false;
    }
    
    return true;
}

void LLVMCodeGenerator::dumpModule() {
    module->print(llvm::errs(), nullptr);
}

bool LLVMCodeGenerator::emitObjectFile(const std::string& filename) {
    if (!target_machine) {
        logError("Target machine not initialized");
        return false;
    }
    
    std::error_code error_code;
    llvm::raw_fd_ostream dest(filename, error_code, llvm::sys::fs::OF_None);
    
    if (error_code) {
        logError("Could not open file: " + error_code.message());
        return false;
    }
    
    llvm::legacy::PassManager pass;
    auto file_type = llvm::CGFT_ObjectFile;
    
    if (target_machine->addPassesToEmitFile(pass, dest, nullptr, file_type)) {
        logError("TargetMachine can't emit a file of this type");
        return false;
    }
    
    pass.run(*module);
    dest.flush();
    
    return true;
}

bool LLVMCodeGenerator::linkExecutable(const std::string& output_file, const std::string& object_file) {
    // This is a simplified linking - in practice you'd use system linker
    std::string link_cmd;
    
#ifdef _WIN32
    link_cmd = "link.exe /OUT:" + output_file + " " + object_file + " msvcrt.lib";
#else
    link_cmd = "gcc -o " + output_file + " " + object_file;
#endif
    
    int result = system(link_cmd.c_str());
    return result == 0;
}

void LLVMCodeGenerator::logError(const std::string& message) {
    hasError = true;
    error_message = message;
    std::cerr << "Error: " << message << std::endl;
}

} // namespace zen