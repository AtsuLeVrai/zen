#pragma once

#include "token.h"
#include <vector>
#include <string>
#include <memory>
#include <unordered_map>

namespace zen {

class Lexer {
private:
    std::string source;
    size_t current;
    int line;
    int column;
    std::vector<std::unique_ptr<Token>> tokens;
    
    static const std::unordered_map<std::string, TokenType> keywords;
    
    char peek(size_t offset = 0) const;
    char advance();
    bool isAtEnd() const;
    bool isAlpha(char c) const;
    bool isAlphaNumeric(char c) const;
    bool isDigit(char c) const;
    
    void scanToken();
    void addToken(TokenType type);
    void addToken(TokenType type, const std::string& lexeme);
    
    void scanString();
    void scanNumber();
    void scanIdentifier();
    void scanComment();
    void skipWhitespace();

public:
    explicit Lexer(const std::string& source);
    ~Lexer() = default;
    
    std::vector<std::unique_ptr<Token>> scanTokens();
};

} // namespace zen