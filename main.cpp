#include <iostream>
#include <string>
#include <memory>
#include <fstream>
#include <sstream>
#include <filesystem>

#include "src/lexer/lexer.h"
#include "src/parser/parser.h"
#include "src/ast/ast_node.h"
#include "src/codegen/llvm_codegen.h"

using namespace zen;

void printTokens(const std::vector<std::unique_ptr<Token>>& tokens)
{
    std::cout << "\n=== LEXER OUTPUT ===" << std::endl;
    std::cout << "Tokens found: " << tokens.size() << std::endl;

    for (const auto& token : tokens)
    {
        std::cout << "  [" << token->line << ":" << token->column << "] ";

        switch (token->type)
        {
        case TokenType::FUNC: std::cout << "FUNC";
            break;
        case TokenType::IDENTIFIER: std::cout << "ID(" << token->lexeme << ")";
            break;
        case TokenType::NUMBER: std::cout << "NUM(" << token->lexeme << ")";
            break;
        case TokenType::STRING: std::cout << "STR(\"" << token->lexeme << "\")";
            break;
        case TokenType::LEFT_PAREN: std::cout << "(";
            break;
        case TokenType::RIGHT_PAREN: std::cout << ")";
            break;
        case TokenType::LEFT_BRACE: std::cout << "{";
            break;
        case TokenType::RIGHT_BRACE: std::cout << "}";
            break;
        case TokenType::SEMICOLON: std::cout << ";";
            break;
        case TokenType::COLON: std::cout << ":";
            break;
        case TokenType::ARROW: std::cout << "->";
            break;
        case TokenType::I32: std::cout << "i32";
            break;
        case TokenType::STRING_TYPE: std::cout << "string";
            break;
        case TokenType::RETURN: std::cout << "RETURN";
            break;
        case TokenType::END_OF_FILE: std::cout << "EOF";
            break;
        default: std::cout << "TOKEN(" << static_cast<int>(token->type) << ")";
            break;
        }
        std::cout << std::endl;
    }
}

void analyzeAST(const std::unique_ptr<ASTNode>& node, int depth = 0)
{
    if (!node) return;

    std::string indent(depth * 2, ' ');

    switch (node->type)
    {
    case ASTNodeType::PROGRAM:
        {
            std::cout << indent << "Program" << std::endl;
            auto* program = static_cast<ProgramNode*>(node.get());
            for (const auto& decl : program->declarations)
            {
                analyzeAST(decl, depth + 1);
            }
            break;
        }
    case ASTNodeType::FUNCTION_DECLARATION:
        {
            auto* func = static_cast<FunctionDeclarationNode*>(node.get());
            std::cout << indent << "Function: " << func->name
                << " -> " << func->return_type << std::endl;
            std::cout << indent << "  Parameters: " << func->parameters.size() << std::endl;
            if (func->body)
            {
                analyzeAST(func->body, depth + 1);
            }
            break;
        }
    case ASTNodeType::BLOCK_STATEMENT:
        {
            auto* block = static_cast<BlockStatementNode*>(node.get());
            std::cout << indent << "Block (" << block->statements.size() << " statements)" << std::endl;
            for (const auto& stmt : block->statements)
            {
                analyzeAST(stmt, depth + 1);
            }
            break;
        }
    case ASTNodeType::RETURN_STATEMENT:
        {
            std::cout << indent << "Return Statement" << std::endl;
            auto* ret = static_cast<ReturnStatementNode*>(node.get());
            if (ret->value)
            {
                analyzeAST(ret->value, depth + 1);
            }
            break;
        }
    case ASTNodeType::LITERAL:
        {
            auto* lit = static_cast<LiteralNode*>(node.get());
            std::cout << indent << "Literal: " << lit->value << std::endl;
            break;
        }
    case ASTNodeType::IDENTIFIER:
        {
            auto* id = static_cast<IdentifierNode*>(node.get());
            std::cout << indent << "Identifier: " << id->name << std::endl;
            break;
        }
    default:
        std::cout << indent << "Node (type: " << static_cast<int>(node->type) << ")" << std::endl;
        break;
    }
}

std::string readFile(const std::string& filename)
{
    std::ifstream file(filename);
    if (!file.is_open())
    {
        return "";
    }

    std::stringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}

int main(int argc, char* argv[])
{
    try
    {
        std::cout << "=== ZEN COMPILER v0.1 ===" << std::endl;
        std::cout << "Zen Language Compiler" << std::endl;

        // Vérifier les arguments
        if (argc != 2)
        {
            std::cout << "\nUsage: " << argv[0] << " <file.zen>" << std::endl;
            std::cout << "Example: " << argv[0] << " ./examples/hello.zen" << std::endl;
            return 1;
        }

        std::string filename = argv[1];
        std::cout << "Compiling: " << filename << std::endl;

        // Lire le fichier
        std::string zen_code = readFile(filename);
        if (zen_code.empty())
        {
            std::cerr << "ERROR: Could not read file '" << filename << "'" << std::endl;
            std::cerr << "Make sure the file exists and is readable." << std::endl;
            return 1;
        }

        std::cout << "\n=== SOURCE CODE ===" << std::endl;
        std::cout << "File: " << filename << " (" << zen_code.length() << " characters)" << std::endl;
        std::cout << zen_code << std::endl;

        // Phase 1: Lexical Analysis
        std::cout << "\n--- Phase 1: Lexical Analysis ---" << std::endl;
        Lexer lexer(zen_code);
        auto tokens = lexer.scanTokens();

        if (tokens.empty())
        {
            std::cerr << "ERROR: No tokens generated!" << std::endl;
            return 1;
        }

        printTokens(tokens);

        // Phase 2: Syntax Analysis
        std::cout << "\n--- Phase 2: Syntax Analysis ---" << std::endl;
        Parser parser(std::move(tokens));
        auto ast = parser.parse();

        if (!ast)
        {
            std::cerr << "ERROR: Failed to parse!" << std::endl;
            return 1;
        }

        std::cout << "\n=== AST STRUCTURE ===" << std::endl;
        analyzeAST(ast);

        // Phase 3: LLVM Code Generation
        std::cout << "\n--- Phase 3: LLVM Code Generation ---" << std::endl;
        
        // Create output filenames
        std::filesystem::path input_path(filename);
        std::string base_name = input_path.stem().string();
        std::string object_file = base_name + ".o";
        std::string executable_file = base_name + ".exe";
        
        // Initialize LLVM code generator
        LLVMCodeGenerator codegen(base_name);
        
        // Generate LLVM IR from AST
        std::cout << "Generating LLVM IR..." << std::endl;
        if (!codegen.generateProgram(static_cast<ProgramNode*>(ast.get()))) {
            std::cerr << "ERROR: Failed to generate LLVM IR!" << std::endl;
            return 1;
        }
        
        std::cout << "✅ LLVM IR generated successfully" << std::endl;
        
        // Dump the generated LLVM IR for debugging
        std::cout << "\n=== GENERATED LLVM IR ===" << std::endl;
        codegen.dumpModule();
        
        // Emit object file
        std::cout << "\nEmitting object file: " << object_file << std::endl;
        if (!codegen.emitObjectFile(object_file)) {
            std::cerr << "ERROR: Failed to emit object file!" << std::endl;
            return 1;
        }
        
        std::cout << "✅ Object file generated: " << object_file << std::endl;
        
        // Link executable
        std::cout << "Linking executable: " << executable_file << std::endl;
        if (!codegen.linkExecutable(executable_file, object_file)) {
            std::cerr << "ERROR: Failed to link executable!" << std::endl;
            return 1;
        }
        
        std::cout << "✅ Executable generated: " << executable_file << std::endl;

        // Phase Summary
        std::cout << "\n--- Compilation Summary ---" << std::endl;
        std::cout << "✅ Lexer: Working" << std::endl;
        std::cout << "✅ Parser: Working" << std::endl;
        std::cout << "✅ LLVM Code Generation: Working" << std::endl;
        std::cout << "✅ Object File Emission: Working" << std::endl;
        std::cout << "✅ Executable Linking: Working" << std::endl;
        std::cout << "🔄 Advanced Features: TODO (Phase 2)" << std::endl;

        std::cout << "\n=== PHASE 1 SUCCESS ===" << std::endl;
        std::cout << "Zen LLVM compiler Phase 1 complete! 🚀" << std::endl;
        std::cout << "Generated native executable: " << executable_file << std::endl;
        std::cout << "\nTo test: ./" << executable_file << std::endl;

        std::cout << "\nPress Enter to exit..." << std::endl;
        std::cin.get();
    }
    catch (const std::exception& e)
    {
        std::cerr << "\nFATAL ERROR: " << e.what() << std::endl;
        std::cout << "Press Enter to exit..." << std::endl;
        std::cin.get();
        return 1;
    }

    return 0;
}
