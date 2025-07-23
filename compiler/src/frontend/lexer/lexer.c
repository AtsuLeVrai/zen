#include "lexer.h"
#include <string.h>
#include <ctype.h>
#include <stdio.h>

// Keyword mapping structure
typedef struct {
    const char *keyword;
    TokenType token_type;
} KeywordMapping;

// All Zen language keywords
static const KeywordMapping keywords[] = {
    {"func", TOKEN_FUNC},
    {"let", TOKEN_LET},
    {"const", TOKEN_CONST},
    {"return", TOKEN_RETURN},
    {"if", TOKEN_IF},
    {"else", TOKEN_ELSE},
    {"for", TOKEN_FOR},
    {"while", TOKEN_WHILE},
    {"in", TOKEN_IN},
    {"true", TOKEN_TRUE},
    {"false", TOKEN_FALSE},
    {"null", TOKEN_NULL},
    {"type", TOKEN_TYPE},
    {"import", TOKEN_IMPORT},
    {"export", TOKEN_EXPORT},
    {"async", TOKEN_ASYNC},
    {"await", TOKEN_AWAIT},
    {"throw", TOKEN_THROW},
    {"catch", TOKEN_CATCH},
    {"try", TOKEN_TRY},
    {"switch", TOKEN_SWITCH},
    {"case", TOKEN_CASE},
    {"default", TOKEN_DEFAULT},
    {"i32", TOKEN_I32},
    {"f64", TOKEN_F64},
    {"string", TOKEN_STRING_TYPE},
    {"bool", TOKEN_BOOL},
    {"void", TOKEN_VOID},
    {"is", TOKEN_IS},
    {NULL, TOKEN_EOF} // Sentinel
};

void lexer_init(Lexer *lexer, const char *source) {
    lexer->start = source;
    lexer->current = source;
    lexer->line = 1;
    lexer->column = 1;
}

static bool is_at_end(Lexer *lexer) {
    return *lexer->current == '\0';
}

static char advance(Lexer *lexer) {
    if (is_at_end(lexer)) return '\0';

    char c = *lexer->current;
    lexer->current++;

    if (c == '\n') {
        lexer->line++;
        lexer->column = 1;
    } else {
        lexer->column++;
    }

    return c;
}

static char peek(Lexer *lexer) {
    return *lexer->current;
}

static char peek_next(Lexer *lexer) {
    if (is_at_end(lexer)) return '\0';
    return lexer->current[1];
}

static bool match(Lexer *lexer, char expected) {
    if (is_at_end(lexer)) return false;
    if (*lexer->current != expected) return false;

    advance(lexer);
    return true;
}

static Token make_token(Lexer *lexer, TokenType type) {
    Token token;
    token.type = type;
    token.start = lexer->start;
    token.length = (int) (lexer->current - lexer->start);
    token.line = lexer->line;
    token.column = lexer->column - token.length;
    return token;
}

static Token error_token(Lexer *lexer, const char *message) {
    Token token;
    token.type = TOKEN_ERROR;
    token.start = message;
    token.length = (int) strlen(message);
    token.line = lexer->line;
    token.column = lexer->column;
    return token;
}

static void skip_whitespace(Lexer *lexer) {
    for (;;) {
        char c = peek(lexer);
        switch (c) {
            case ' ':
            case '\r':
            case '\t':
                advance(lexer);
                break;
            case '/':
                if (peek_next(lexer) == '/') {
                    // Single line comment
                    while (peek(lexer) != '\n' && !is_at_end(lexer)) {
                        advance(lexer);
                    }
                } else if (peek_next(lexer) == '*') {
                    // Multi line comment
                    advance(lexer); // consume '/'
                    advance(lexer); // consume '*'

                    while (!is_at_end(lexer)) {
                        if (peek(lexer) == '*' && peek_next(lexer) == '/') {
                            advance(lexer); // consume '*'
                            advance(lexer); // consume '/'
                            break;
                        }
                        advance(lexer);
                    }
                } else {
                    return;
                }
                break;
            default:
                return;
        }
    }
}

bool is_keyword(const char *text, int length, TokenType *token_type) {
    for (int i = 0; keywords[i].keyword != NULL; i++) {
        if ((int)strlen(keywords[i].keyword) == length &&
            memcmp(text, keywords[i].keyword, (size_t)length) == 0) {
            *token_type = keywords[i].token_type;
            return true;
        }
    }
    return false;
}

static Token identifier(Lexer *lexer) {
    while (isalnum(peek(lexer)) || peek(lexer) == '_') {
        advance(lexer);
    }

    TokenType type;
    if (is_keyword(lexer->start, (int) (lexer->current - lexer->start), &type)) {
        return make_token(lexer, type);
    }

    return make_token(lexer, TOKEN_IDENTIFIER);
}

static Token number(Lexer *lexer) {
    while (isdigit(peek(lexer))) {
        advance(lexer);
    }

    // Look for fractional part
    if (peek(lexer) == '.' && isdigit(peek_next(lexer))) {
        advance(lexer); // consume '.'

        while (isdigit(peek(lexer))) {
            advance(lexer);
        }
    }

    return make_token(lexer, TOKEN_NUMBER);
}

static Token string_literal(Lexer *lexer) {
    while (peek(lexer) != '"' && !is_at_end(lexer)) {
        if (peek(lexer) == '\\') {
            advance(lexer); // consume backslash
            if (!is_at_end(lexer)) {
                advance(lexer); // consume escaped character
            }
        } else {
            advance(lexer);
        }
    }

    if (is_at_end(lexer)) {
        return error_token(lexer, "Unterminated string");
    }

    advance(lexer); // consume closing quote
    return make_token(lexer, TOKEN_STRING);
}

static Token template_string(Lexer *lexer) {
    while (peek(lexer) != '`' && !is_at_end(lexer)) {
        if (peek(lexer) == '$' && peek_next(lexer) == '{') {
            // Found string interpolation, return current string part
            if (lexer->current > lexer->start) {
                return make_token(lexer, TOKEN_STRING);
            }
            // Return the ${ token
            advance(lexer); // consume '$'
            advance(lexer); // consume '{'
            return make_token(lexer, TOKEN_DOLLAR_LEFT_BRACE);
        }

        if (peek(lexer) == '\\') {
            advance(lexer); // consume backslash
            if (!is_at_end(lexer)) {
                advance(lexer); // consume escaped character
            }
        } else {
            advance(lexer);
        }
    }

    if (is_at_end(lexer)) {
        return error_token(lexer, "Unterminated template string");
    }

    advance(lexer); // consume closing backtick
    return make_token(lexer, TOKEN_STRING);
}

Token lexer_next_token(Lexer *lexer) {
    skip_whitespace(lexer);

    lexer->start = lexer->current;

    if (is_at_end(lexer)) {
        return make_token(lexer, TOKEN_EOF);
    }

    char c = advance(lexer);

    if (isalpha(c) || c == '_') {
        return identifier(lexer);
    }

    if (isdigit(c)) {
        return number(lexer);
    }

    switch (c) {
        case '(': return make_token(lexer, TOKEN_LEFT_PAREN);
        case ')': return make_token(lexer, TOKEN_RIGHT_PAREN);
        case '{': return make_token(lexer, TOKEN_LEFT_BRACE);
        case '}': return make_token(lexer, TOKEN_RIGHT_BRACE);
        case '[': return make_token(lexer, TOKEN_LEFT_BRACKET);
        case ']': return make_token(lexer, TOKEN_RIGHT_BRACKET);
        case ',': return make_token(lexer, TOKEN_COMMA);
        case ';': return make_token(lexer, TOKEN_SEMICOLON);
        case ':': return make_token(lexer, TOKEN_COLON);
        case '?': return make_token(lexer, TOKEN_QUESTION);
        case '@': return make_token(lexer, TOKEN_AT);
        case '\n': return make_token(lexer, TOKEN_NEWLINE);

        case '+':
            return make_token(lexer, match(lexer, '=') ? TOKEN_PLUS_ASSIGN : TOKEN_PLUS);
        case '-':
            if (match(lexer, '=')) return make_token(lexer, TOKEN_MINUS_ASSIGN);
            if (match(lexer, '>')) return make_token(lexer, TOKEN_ARROW);
            return make_token(lexer, TOKEN_MINUS);
        case '*':
            return make_token(lexer, match(lexer, '=') ? TOKEN_MULTIPLY_ASSIGN : TOKEN_MULTIPLY);
        case '/':
            return make_token(lexer, match(lexer, '=') ? TOKEN_DIVIDE_ASSIGN : TOKEN_DIVIDE);
        case '%':
            return make_token(lexer, TOKEN_MODULO);

        case '!':
            return make_token(lexer, match(lexer, '=') ? TOKEN_NOT_EQUAL : TOKEN_NOT);
        case '=':
            return make_token(lexer, match(lexer, '=') ? TOKEN_EQUAL : TOKEN_ASSIGN);
        case '<':
            return make_token(lexer, match(lexer, '=') ? TOKEN_LESS_EQUAL : TOKEN_LESS);
        case '>':
            return make_token(lexer, match(lexer, '=') ? TOKEN_GREATER_EQUAL : TOKEN_GREATER);

        case '&':
            if (match(lexer, '&')) return make_token(lexer, TOKEN_AND);
            return error_token(lexer, "Unexpected character '&'");
        case '|':
            if (match(lexer, '|')) return make_token(lexer, TOKEN_OR);
            return error_token(lexer, "Unexpected character '|'");

        case '.':
            if (match(lexer, '.')) return make_token(lexer, TOKEN_RANGE);
            return make_token(lexer, TOKEN_DOT);

        case '"':
            return string_literal(lexer);
        case '`':
            return template_string(lexer);
    }

    return error_token(lexer, "Unexpected character");
}

const char *token_type_to_string(TokenType type) {
    switch (type) {
        case TOKEN_EOF: return "EOF";
        case TOKEN_NUMBER: return "NUMBER";
        case TOKEN_STRING: return "STRING";
        case TOKEN_IDENTIFIER: return "IDENTIFIER";
        case TOKEN_FUNC: return "FUNC";
        case TOKEN_LET: return "LET";
        case TOKEN_CONST: return "CONST";
        case TOKEN_RETURN: return "RETURN";
        case TOKEN_IF: return "IF";
        case TOKEN_ELSE: return "ELSE";
        case TOKEN_FOR: return "FOR";
        case TOKEN_WHILE: return "WHILE";
        case TOKEN_IN: return "IN";
        case TOKEN_TRUE: return "TRUE";
        case TOKEN_FALSE: return "FALSE";
        case TOKEN_NULL: return "NULL";
        case TOKEN_TYPE: return "TYPE";
        case TOKEN_IMPORT: return "IMPORT";
        case TOKEN_EXPORT: return "EXPORT";
        case TOKEN_ASYNC: return "ASYNC";
        case TOKEN_AWAIT: return "AWAIT";
        case TOKEN_THROW: return "THROW";
        case TOKEN_CATCH: return "CATCH";
        case TOKEN_TRY: return "TRY";
        case TOKEN_SWITCH: return "SWITCH";
        case TOKEN_CASE: return "CASE";
        case TOKEN_DEFAULT: return "DEFAULT";
        case TOKEN_I32: return "I32";
        case TOKEN_F64: return "F64";
        case TOKEN_STRING_TYPE: return "STRING_TYPE";
        case TOKEN_BOOL: return "BOOL";
        case TOKEN_VOID: return "VOID";
        case TOKEN_PLUS: return "PLUS";
        case TOKEN_MINUS: return "MINUS";
        case TOKEN_MULTIPLY: return "MULTIPLY";
        case TOKEN_DIVIDE: return "DIVIDE";
        case TOKEN_MODULO: return "MODULO";
        case TOKEN_ASSIGN: return "ASSIGN";
        case TOKEN_PLUS_ASSIGN: return "PLUS_ASSIGN";
        case TOKEN_MINUS_ASSIGN: return "MINUS_ASSIGN";
        case TOKEN_MULTIPLY_ASSIGN: return "MULTIPLY_ASSIGN";
        case TOKEN_DIVIDE_ASSIGN: return "DIVIDE_ASSIGN";
        case TOKEN_EQUAL: return "EQUAL";
        case TOKEN_NOT_EQUAL: return "NOT_EQUAL";
        case TOKEN_LESS: return "LESS";
        case TOKEN_LESS_EQUAL: return "LESS_EQUAL";
        case TOKEN_GREATER: return "GREATER";
        case TOKEN_GREATER_EQUAL: return "GREATER_EQUAL";
        case TOKEN_AND: return "AND";
        case TOKEN_OR: return "OR";
        case TOKEN_NOT: return "NOT";
        case TOKEN_IS: return "IS";
        case TOKEN_QUESTION: return "QUESTION";
        case TOKEN_ARROW: return "ARROW";
        case TOKEN_RANGE: return "RANGE";
        case TOKEN_LEFT_PAREN: return "LEFT_PAREN";
        case TOKEN_RIGHT_PAREN: return "RIGHT_PAREN";
        case TOKEN_LEFT_BRACE: return "LEFT_BRACE";
        case TOKEN_RIGHT_BRACE: return "RIGHT_BRACE";
        case TOKEN_LEFT_BRACKET: return "LEFT_BRACKET";
        case TOKEN_RIGHT_BRACKET: return "RIGHT_BRACKET";
        case TOKEN_COMMA: return "COMMA";
        case TOKEN_SEMICOLON: return "SEMICOLON";
        case TOKEN_COLON: return "COLON";
        case TOKEN_DOT: return "DOT";
        case TOKEN_NEWLINE: return "NEWLINE";
        case TOKEN_AT: return "AT";
        case TOKEN_DOLLAR_LEFT_BRACE: return "DOLLAR_LEFT_BRACE";
        case TOKEN_ERROR: return "ERROR";
        default: return "UNKNOWN";
    }
}
