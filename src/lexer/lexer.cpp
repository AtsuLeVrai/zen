#include "lexer.h"
#include <cctype>
#include <iostream>

namespace zen {

const std::unordered_map<std::string, TokenType> Lexer::keywords = {
    {"func", TokenType::FUNC},
    {"let", TokenType::LET},
    {"const", TokenType::CONST},
    {"type", TokenType::TYPE},
    {"import", TokenType::IMPORT},
    {"export", TokenType::EXPORT},
    {"if", TokenType::IF},
    {"else", TokenType::ELSE},
    {"for", TokenType::FOR},
    {"while", TokenType::WHILE},
    {"switch", TokenType::SWITCH},
    {"case", TokenType::CASE},
    {"default", TokenType::DEFAULT},
    {"return", TokenType::RETURN},
    {"throw", TokenType::THROW},
    {"catch", TokenType::CATCH},
    {"try", TokenType::TRY},
    {"async", TokenType::ASYNC},
    {"await", TokenType::AWAIT},
    {"in", TokenType::IN},
    {"is", TokenType::IS},
    {"i32", TokenType::I32},
    {"f64", TokenType::F64},
    {"string", TokenType::STRING_TYPE},
    {"bool", TokenType::BOOL},
    {"void", TokenType::VOID},
    {"target", TokenType::TARGET},
    {"hotpatch", TokenType::HOTPATCH},
};

Lexer::Lexer(const std::string& source) 
    : source(source), current(0), line(1), column(1) {}

std::vector<std::unique_ptr<Token>> Lexer::scanTokens() {
    while (!isAtEnd()) {
        scanToken();
    }
    
    addToken(TokenType::END_OF_FILE);
    return std::move(tokens);
}

char Lexer::peek(size_t offset) const {
    size_t position = current + offset;
    if (position >= source.length()) {
        return '\0';
    }
    return source[position];
}

char Lexer::advance() {
    if (isAtEnd()) return '\0';
    
    char c = source[current++];
    if (c == '\n') {
        line++;
        column = 1;
    } else {
        column++;
    }
    return c;
}

bool Lexer::isAtEnd() const {
    return current >= source.length();
}

bool Lexer::isAlpha(char c) const {
    return std::isalpha(c) || c == '_';
}

bool Lexer::isAlphaNumeric(char c) const {
    return isAlpha(c) || isDigit(c);
}

bool Lexer::isDigit(char c) const {
    return std::isdigit(c);
}

void Lexer::scanToken() {
    char c = advance();
    
    switch (c) {
        case ' ':
        case '\r':
        case '\t':
            break;
        case '\n':
            addToken(TokenType::NEWLINE);
            break;
        case '(':
            addToken(TokenType::LEFT_PAREN);
            break;
        case ')':
            addToken(TokenType::RIGHT_PAREN);
            break;
        case '{':
            addToken(TokenType::LEFT_BRACE);
            break;
        case '}':
            addToken(TokenType::RIGHT_BRACE);
            break;
        case '[':
            addToken(TokenType::LEFT_BRACKET);
            break;
        case ']':
            addToken(TokenType::RIGHT_BRACKET);
            break;
        case ',':
            addToken(TokenType::COMMA);
            break;
        case '.':
            addToken(TokenType::DOT);
            break;
        case ';':
            addToken(TokenType::SEMICOLON);
            break;
        case ':':
            addToken(TokenType::COLON);
            break;
        case '?':
            addToken(TokenType::QUESTION);
            break;
        case '@':
            addToken(TokenType::AT);
            break;
        case '+':
            if (peek() == '=') {
                advance();
                addToken(TokenType::PLUS_ASSIGN);
            } else {
                addToken(TokenType::PLUS);
            }
            break;
        case '-':
            if (peek() == '=') {
                advance();
                addToken(TokenType::MINUS_ASSIGN);
            } else if (peek() == '>') {
                advance();
                addToken(TokenType::ARROW);
            } else {
                addToken(TokenType::MINUS);
            }
            break;
        case '*':
            if (peek() == '=') {
                advance();
                addToken(TokenType::MULTIPLY_ASSIGN);
            } else {
                addToken(TokenType::MULTIPLY);
            }
            break;
        case '/':
            if (peek() == '=') {
                advance();
                addToken(TokenType::DIVIDE_ASSIGN);
            } else if (peek() == '/') {
                scanComment();
            } else if (peek() == '*') {
                advance();
                advance();
                while (!isAtEnd() && !(peek() == '*' && peek(1) == '/')) {
                    advance();
                }
                if (!isAtEnd()) {
                    advance(); // *
                    advance(); // /
                }
            } else {
                addToken(TokenType::DIVIDE);
            }
            break;
        case '%':
            addToken(TokenType::MODULO);
            break;
        case '=':
            if (peek() == '=') {
                advance();
                addToken(TokenType::EQUAL);
            } else {
                addToken(TokenType::ASSIGN);
            }
            break;
        case '!':
            if (peek() == '=') {
                advance();
                addToken(TokenType::NOT_EQUAL);
            } else {
                addToken(TokenType::NOT);
            }
            break;
        case '<':
            if (peek() == '=') {
                advance();
                addToken(TokenType::LESS_EQUAL);
            } else {
                addToken(TokenType::LESS_THAN);
            }
            break;
        case '>':
            if (peek() == '=') {
                advance();
                addToken(TokenType::GREATER_EQUAL);
            } else {
                addToken(TokenType::GREATER_THAN);
            }
            break;
        case '&':
            if (peek() == '&') {
                advance();
                addToken(TokenType::AND);
            }
            break;
        case '|':
            if (peek() == '|') {
                advance();
                addToken(TokenType::OR);
            }
            break;
        case '"':
            scanString();
            break;
        default:
            if (isDigit(c)) {
                current--; // Back up to re-scan the digit
                column--;
                scanNumber();
            } else if (isAlpha(c)) {
                current--; // Back up to re-scan the character
                column--;
                scanIdentifier();
            } else {
                addToken(TokenType::INVALID);
                std::cerr << "Unexpected character '" << c << "' at line " << line << ", column " << column << std::endl;
            }
            break;
    }
}

void Lexer::addToken(TokenType type) {
    addToken(type, "");
}

void Lexer::addToken(TokenType type, const std::string& lexeme) {
    tokens.push_back(std::make_unique<Token>(type, lexeme, line, column));
}

void Lexer::scanString() {
    std::string value;
    
    while (peek() != '"' && !isAtEnd()) {
        if (peek() == '\n') {
            line++;
            column = 1;
        } else {
            column++;
        }
        
        if (peek() == '\\') {
            advance(); // consume backslash
            char escaped = advance();
            switch (escaped) {
                case 'n': value += '\n'; break;
                case 't': value += '\t'; break;
                case 'r': value += '\r'; break;
                case '\\': value += '\\'; break;
                case '"': value += '"'; break;
                default: value += escaped; break;
            }
        } else {
            value += advance();
        }
    }
    
    if (isAtEnd()) {
        std::cerr << "Unterminated string at line " << line << std::endl;
        addToken(TokenType::INVALID);
        return;
    }
    
    advance(); // closing "
    addToken(TokenType::STRING, value);
}

void Lexer::scanNumber() {
    std::string value;
    
    while (isDigit(peek())) {
        value += advance();
    }
    
    if (peek() == '.' && isDigit(peek(1))) {
        value += advance(); // consume the .
        while (isDigit(peek())) {
            value += advance();
        }
    }
    
    addToken(TokenType::NUMBER, value);
}

void Lexer::scanIdentifier() {
    std::string value;
    
    while (isAlphaNumeric(peek())) {
        value += advance();
    }
    
    auto keyword = keywords.find(value);
    TokenType type = (keyword != keywords.end()) ? keyword->second : TokenType::IDENTIFIER;
    
    addToken(type, value);
}

void Lexer::scanComment() {
    while (peek() != '\n' && !isAtEnd()) {
        advance();
    }
}

} // namespace zen