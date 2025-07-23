#ifndef ZEN_LEXER_H
#define ZEN_LEXER_H

#include <stdint.h>
#include <stdbool.h>

// Token types for Zen language
typedef enum {
    TOKEN_EOF = 0,
    
    // Literals
    TOKEN_NUMBER,
    TOKEN_STRING,
    TOKEN_IDENTIFIER,
    
    // Keywords
    TOKEN_FUNC,
    TOKEN_LET,
    TOKEN_CONST,
    TOKEN_RETURN,
    TOKEN_IF,
    TOKEN_ELSE,
    TOKEN_FOR,
    TOKEN_WHILE,
    TOKEN_IN,
    TOKEN_TRUE,
    TOKEN_FALSE,
    TOKEN_NULL,
    TOKEN_TYPE,
    TOKEN_IMPORT,
    TOKEN_EXPORT,
    TOKEN_ASYNC,
    TOKEN_AWAIT,
    TOKEN_THROW,
    TOKEN_CATCH,
    TOKEN_TRY,
    TOKEN_SWITCH,
    TOKEN_CASE,
    TOKEN_DEFAULT,
    
    // Types
    TOKEN_I32,
    TOKEN_F64,
    TOKEN_STRING_TYPE,
    TOKEN_BOOL,
    TOKEN_VOID,
    
    // Operators
    TOKEN_PLUS,
    TOKEN_MINUS,
    TOKEN_MULTIPLY,
    TOKEN_DIVIDE,
    TOKEN_MODULO,
    TOKEN_ASSIGN,
    TOKEN_PLUS_ASSIGN,
    TOKEN_MINUS_ASSIGN,
    TOKEN_MULTIPLY_ASSIGN,
    TOKEN_DIVIDE_ASSIGN,
    TOKEN_EQUAL,
    TOKEN_NOT_EQUAL,
    TOKEN_LESS,
    TOKEN_LESS_EQUAL,
    TOKEN_GREATER,
    TOKEN_GREATER_EQUAL,
    TOKEN_AND,
    TOKEN_OR,
    TOKEN_NOT,
    TOKEN_IS,
    TOKEN_QUESTION,
    TOKEN_ARROW,
    TOKEN_RANGE,
    
    // Delimiters
    TOKEN_LEFT_PAREN,
    TOKEN_RIGHT_PAREN,
    TOKEN_LEFT_BRACE,
    TOKEN_RIGHT_BRACE,
    TOKEN_LEFT_BRACKET,
    TOKEN_RIGHT_BRACKET,
    TOKEN_COMMA,
    TOKEN_SEMICOLON,
    TOKEN_COLON,
    TOKEN_DOT,
    
    // Special
    TOKEN_NEWLINE,
    TOKEN_AT,
    TOKEN_DOLLAR_LEFT_BRACE,
    
    // Error
    TOKEN_ERROR
} TokenType;

typedef struct {
    TokenType type;
    const char* start;
    int length;
    int line;
    int column;
} Token;

typedef struct {
    const char* start;
    const char* current;
    int line;
    int column;
} Lexer;

// Function declarations
void lexer_init(Lexer* lexer, const char* source);
Token lexer_next_token(Lexer* lexer);
const char* token_type_to_string(TokenType type);
bool is_keyword(const char* text, int length, TokenType* token_type);

#endif // ZEN_LEXER_H