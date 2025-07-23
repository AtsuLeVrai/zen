#ifndef ZEN_PARSER_H
#define ZEN_PARSER_H

#include "lexer.h"
#include "ast.h"
#include <stdbool.h>

// Error types for better error reporting
typedef enum {
    PARSE_ERROR_NONE,
    PARSE_ERROR_UNEXPECTED_TOKEN,
    PARSE_ERROR_MISSING_TOKEN,
    PARSE_ERROR_INVALID_EXPRESSION,
    PARSE_ERROR_INVALID_STATEMENT,
    PARSE_ERROR_MEMORY_ERROR
} ParseErrorType;

typedef struct {
    ParseErrorType type;
    Token token;
    char* message;
    int line;
    int column;
} ParseError;

typedef struct {
    Lexer* lexer;
    Token current;
    Token previous;
    bool had_error;
    bool panic_mode;
    ParseError error;
    ASTArena* arena;
} Parser;

// Precedence levels for expressions
typedef enum {
    PREC_NONE,
    PREC_ASSIGNMENT,  // =
    PREC_OR,          // ||
    PREC_AND,         // &&
    PREC_EQUALITY,    // == !=
    PREC_COMPARISON,  // > >= < <=
    PREC_TERM,        // + -
    PREC_FACTOR,      // * / %
    PREC_UNARY,       // ! -
    PREC_CALL,        // . ()
    PREC_PRIMARY
} Precedence;

// Function pointer types for parsing
typedef ASTNode* (*PrefixParseFn)(Parser* parser);
typedef ASTNode* (*InfixParseFn)(Parser* parser, ASTNode* left);

// Parse rule structure
typedef struct {
    PrefixParseFn prefix;
    InfixParseFn infix;
    Precedence precedence;
} ParseRule;

// Parser functions
void parser_init(Parser* parser, Lexer* lexer, ASTArena* arena);
void parser_cleanup(Parser* parser);

// Main parsing functions
ASTNode* parse_program(Parser* parser);
ASTNode* parse_declaration(Parser* parser);
ASTNode* parse_statement(Parser* parser);
ASTNode* parse_expression(Parser* parser);
ASTNode* parse_if_statement(Parser* parser);

// Error handling
void parse_error(Parser* parser, const char* message);
void parse_error_at(Parser* parser, Token token, const char* message);
void parse_error_at_current(Parser* parser, const char* message);

// Synchronization
void synchronize(Parser* parser);

#endif // ZEN_PARSER_H