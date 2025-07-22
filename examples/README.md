# Zen Language Examples

This directory contains example programs written in the Zen programming language to demonstrate its features and syntax.

## Examples

### 1. Hello World (`hello_world.zen`)
- Basic function declaration with `func` keyword
- String constants with `const` keyword
- String interpolation with `${}` syntax
- Simple function calls

**Features demonstrated:**
- Function definitions
- String literals and interpolation
- Basic I/O

### 2. Calculator (`calculator.zen`)
- Arithmetic operations and functions
- Error handling with `Result<T, E>` types
- Error propagation with `?` operator
- Custom error types

**Features demonstrated:**
- Function parameters and return types
- Basic arithmetic
- Error handling and propagation
- Type definitions

### 3. Types and Structures (`types_and_structs.zen`)
- Custom type definitions with `type` keyword
- Array types and literals
- Optional types with `?`
- Range operations with `in` operator
- For-in loops

**Features demonstrated:**
- Struct-like types
- Arrays and iteration
- Optional types
- Control flow (if/else, for loops)
- Range checking

### 4. Multi-target (`multi_target.zen`)
- Target-specific compilation with `@target` annotations
- Async/await functionality
- Import declarations
- Hot-patching with `@hotpatch`
- Advanced error handling with catch blocks

**Features demonstrated:**
- Multi-target compilation
- Annotations system
- Async programming
- Module imports
- Advanced error handling patterns

## Running Examples

To compile and run these examples (once the compiler is built):

```bash
# Build the Zen compiler
zig build

# Compile a Zen program to native code
./zig-out/bin/zen examples/hello_world.zen

# Compile for WebAssembly
./zig-out/bin/zen --target wasm examples/calculator.zen

# Compile for hybrid (both native and WASM)
./zig-out/bin/zen --target hybrid examples/multi_target.zen

# Development mode with hot-patching
./zig-out/bin/zen --dev examples/multi_target.zen
```

## Syntax Highlights

### Variables and Types
```zen
let name: string = "John";           // Mutable variable
const age: i32 = 25;                 // Constant
let email: ?string = null;           // Optional type
let numbers: i32[] = [1, 2, 3];      // Array
```

### Functions
```zen
func add(a: i32, b: i32) -> i32 {
    return a + b;
}

async func fetchData() -> Result<Data, Error> {
    // Async function
}
```

### Error Handling
```zen
// Error propagation
let result = divide(10, 2)?;

// Try with default
let safe = try divide(10, 0) else 0;

// Catch blocks
let response = http.get(url) catch {
    NetworkError(msg) => throw UserError(`Network: ${msg}`),
    TimeoutError => return Err(TimeoutError()),
};
```

### Multi-target Code
```zen
@target(wasm, native)
func loadData() -> Result<Data, Error> {
    @target(wasm) {
        return await fetchFromAPI();
    }
    
    @target(native) {
        return await readFromFile("data.json");
    }
}
```

## Note

These examples demonstrate the planned syntax and features of the Zen language. Some advanced features (like async/await, full error handling, and hot-patching) are not yet fully implemented in the current compiler version but are included to show the language's design direction.