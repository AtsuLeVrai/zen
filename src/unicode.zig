const std = @import("std");

pub fn isValidUtf8(bytes: []const u8) bool {
    var i: usize = 0;
    while (i < bytes.len) {
        const byte = bytes[i];
        var sequence_length: u8 = 0;
        
        if (byte & 0x80 == 0) {
            sequence_length = 1;
        } else if (byte & 0xE0 == 0xC0) {
            sequence_length = 2;
        } else if (byte & 0xF0 == 0xE0) {
            sequence_length = 3;
        } else if (byte & 0xF8 == 0xF0) {
            sequence_length = 4;
        } else {
            return false;
        }
        
        if (i + sequence_length > bytes.len) {
            return false;
        }
        
        for (1..sequence_length) |j| {
            if (bytes[i + j] & 0xC0 != 0x80) {
                return false;
            }
        }
        
        i += sequence_length;
    }
    
    return true;
}

pub fn utf8ByteSequenceLength(first_byte: u8) u8 {
    if (first_byte & 0x80 == 0) return 1;
    if (first_byte & 0xE0 == 0xC0) return 2;
    if (first_byte & 0xF0 == 0xE0) return 3;
    if (first_byte & 0xF8 == 0xF0) return 4;
    return 0;
}

pub fn decodeUtf8Codepoint(bytes: []const u8) struct { codepoint: u21, length: u8 } {
    if (bytes.len == 0) return .{ .codepoint = 0, .length = 0 };
    
    const first_byte = bytes[0];
    
    if (first_byte & 0x80 == 0) {
        return .{ .codepoint = first_byte, .length = 1 };
    }
    
    if (first_byte & 0xE0 == 0xC0 and bytes.len >= 2) {
        const codepoint = (@as(u21, first_byte & 0x1F) << 6) |
                         (@as(u21, bytes[1] & 0x3F));
        return .{ .codepoint = codepoint, .length = 2 };
    }
    
    if (first_byte & 0xF0 == 0xE0 and bytes.len >= 3) {
        const codepoint = (@as(u21, first_byte & 0x0F) << 12) |
                         (@as(u21, bytes[1] & 0x3F) << 6) |
                         (@as(u21, bytes[2] & 0x3F));
        return .{ .codepoint = codepoint, .length = 3 };
    }
    
    if (first_byte & 0xF8 == 0xF0 and bytes.len >= 4) {
        const codepoint = (@as(u21, first_byte & 0x07) << 18) |
                         (@as(u21, bytes[1] & 0x3F) << 12) |
                         (@as(u21, bytes[2] & 0x3F) << 6) |
                         (@as(u21, bytes[3] & 0x3F));
        return .{ .codepoint = codepoint, .length = 4 };
    }
    
    return .{ .codepoint = 0xFFFD, .length = 1 };
}