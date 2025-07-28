#pragma once

#include <string>
#include <memory>

namespace zen {

enum class TokenType {
    // Literals
    IDENTIFIER,
    NUMBER,
    STRING,
    
    // Keywords
    FUNC,
    LET,
    CONST,
    TYPE,
    IMPORT,
    EXPORT,
    IF,
    ELSE,
    FOR,
    WHILE,
    SWITCH,
    CASE,
    DEFAULT,
    RETURN,
    THROW,
    CATCH,
    TRY,
    ASYNC,
    AWAIT,
    IN,
    IS,
    
    // Types
    I32,
    F64,
    STRING_TYPE,
    BOOL,
    VOID,
    
    // Special annotations
    TARGET,
    HOTPATCH,
    
    // Operators
    PLUS,
    MINUS,
    MULTIPLY,
    DIVIDE,
    MODULO,
    EQUAL,
    NOT_EQUAL,
    LESS_THAN,
    LESS_EQUAL,
    GREATER_THAN,
    GREATER_EQUAL,
    AND,
    OR,
    NOT,
    ASSIGN,
    PLUS_ASSIGN,
    MINUS_ASSIGN,
    MULTIPLY_ASSIGN,
    DIVIDE_ASSIGN,
    
    // Punctuation
    LEFT_PAREN,
    RIGHT_PAREN,
    LEFT_BRACE,
    RIGHT_BRACE,
    LEFT_BRACKET,
    RIGHT_BRACKET,
    SEMICOLON,
    COMMA,
    DOT,
    COLON,
    QUESTION,
    ARROW,
    AT,
    
    // Special
    NEWLINE,
    END_OF_FILE,
    INVALID
};

struct Token {
    TokenType type;
    std::string lexeme;
    int line;
    int column;
    
    Token(TokenType t, const std::string& lex, int ln, int col)
        : type(t), lexeme(lex), line(ln), column(col) {}
};

} // namespace zen