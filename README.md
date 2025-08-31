# Zen Programming Language

> **Simplicity without sacrifice. Power without complexity.**

---

## 🔬 Concept Status: Research Phase

**This is a conceptual programming language design, not an active development project.** Zen represents experimental ideas about language design philosophy and syntax - no implementation currently exists or is planned in the immediate future.

This documentation serves as a thought experiment and potential foundation for future language development efforts.

---

## Philosophy: Against Needless Complexity

### The Core Problem

Modern programming languages have forgotten that **code is written to be read**. They've become obsessed with theoretical purity and academic concepts, forgetting that real developers need to:

- **Understand code instantly** - No mental gymnastics to parse what's happening
- **Write code naturally** - Syntax that matches how you think about problems  
- **Debug with confidence** - Clear error messages that actually help
- **Ship reliable software** - Memory safety and type safety without fighting the language

### Why Current Languages Fail

**Rust:** Brilliant concepts buried under cognitive overhead
```rust
// What you want to say: "validate this data"
// What Rust makes you write:
fn validate<'a, T: Serialize + Deserialize<'a> + Clone>(
    data: &'a T
) -> Result<ValidatedData<'a, T>, ValidationError<'a>>
```

**C++:** 40 years of backwards compatibility creating syntax chaos
```cpp
// Multiple ways to do everything, none obvious
auto lambda = [&](const auto& x) -> decltype(auto) { 
    return std::forward<decltype(x)>(x).method(); 
};
```

**Go:** Simplicity at the cost of expressiveness
```go
// No generics means endless type assertions and interface{}
result, ok := value.(SomeType)
if !ok { /* handle error */ }
```

**JavaScript/TypeScript:** Runtime surprises hiding behind compile-time promises
```typescript
// "Type safe" until runtime
const user: User = await fetchUser(); // Could be null, undefined, or malformed
```

### The Zen Approach

**One obvious way to do things.** Every syntax choice optimized for **instant comprehension**.

```zen
// Memory management: explicit but safe
func process_data(size: i32) -> Result<string, Error> {
    let buffer = allocate(size);
    defer free(buffer);  // Guaranteed cleanup, obvious syntax
    
    return transform_buffer(buffer);
}

// Error handling: no mental overhead
let result = risky_operation() catch {
    NetworkError(msg) => throw UserError(`Connection failed: ${msg}`),
    ParseError => return "default_value",
};

// Types: exactly what you expect
struct User {
    user_id: string,
    display_name: string,
    email_address: ?string,  // Obviously optional
}
```

**Core Design Principles:**

1. **Predictability over cleverness** - Code should do exactly what it looks like
2. **Explicitness over inference** - Make intent clear, reduce cognitive load
3. **One syntax per concept** - No multiple ways to achieve the same thing
4. **Safety without ceremony** - Memory and type safety with minimal syntax overhead
5. **Error messages as documentation** - Compiler helps you understand and fix problems

### Target Philosophy

Zen is designed for **native systems development** where you need:
- **Learning-friendly syntax** for rapid onboarding
- **Industrial-strength safety** for production reliability  
- **Fine-grained control** when performance matters
- **Zero-overhead abstractions** - pay only for what you use

**Not a replacement for every language.** Zen focuses on native development where clarity, safety, and performance all matter equally.

---

## Complete Language Specification

### Keywords and Tokens

#### Core Keywords
```zen
// Declarations
let const func type struct enum

// Control flow  
if else switch case default while for in break continue return

// Memory and resource management
defer allocate free sizeof alignof

// Error handling
throw catch try Result Ok Err

// Literals and types
null true false void

// Visibility and imports
import export from as

// Async programming  
async await spawn

// Advanced features
unsafe comptime inline
```

#### Reserved for Future Use
```zen
class trait impl where match loop macro yield
```

### Complete Operator Set

#### Arithmetic Operators
```zen
+    // Addition
-    // Subtraction  
*    // Multiplication
/    // Division
%    // Modulo
**   // Exponentiation
```

#### Assignment Operators
```zen
=     // Assignment
+=    // Add assign
-=    // Subtract assign
*=    // Multiply assign
/=    // Divide assign  
%=    // Modulo assign
**=   // Exponent assign
```

#### Comparison Operators
```zen
==    // Equality
!=    // Inequality
<     // Less than
<=    // Less than or equal
>     // Greater than
>=    // Greater than or equal
is    // Reference equality
in    // Range/collection membership
```

#### Logical Operators
```zen
&&    // Logical AND
||    // Logical OR
!     // Logical NOT
```

#### Bitwise Operators
```zen
&     // Bitwise AND
|     // Bitwise OR
^     // Bitwise XOR
~     // Bitwise NOT
<<    // Left shift
>>    // Right shift
&=    // Bitwise AND assign
|=    // Bitwise OR assign  
^=    // Bitwise XOR assign
<<=   // Left shift assign
>>=   // Right shift assign
```

#### Special Operators
```zen
?     // Error propagation / optional chaining
??    // Null coalescing
..    // Range (inclusive)
...   // Range (exclusive)
?.    // Safe navigation
@     // Memory address
*     // Dereference
&     // Reference
```

#### Punctuation and Delimiters
```zen
()    // Function calls, grouping, tuples
[]    // Array indexing, array literals
{}    // Block scope, struct literals
.     // Member access
,     // Separator
;     // Statement terminator
:     // Type annotation
->    // Function return type
=>    // Match/lambda arrow
#     // Attributes
$     // String interpolation delimiter
```

### Type System Specification

#### Primitive Types
```zen
// Integer types
i8 i16 i32 i64 i128 isize    // Signed integers
u8 u16 u32 u64 u128 usize    // Unsigned integers

// Floating point
f32 f64                      // IEEE 754 floating point

// Other primitives  
bool                         // Boolean (true/false)
char                         // Unicode scalar value
string                       // UTF-8 string
void                         // Unit type (no value)
```

#### Composite Types
```zen
// Arrays - fixed size, homogeneous
[T; N]          // Fixed array: [i32; 5]
T[]             // Dynamic array: i32[]

// Optional types
?T              // Optional: ?string (can be null)

// Function types  
(T, U) -> R     // Function taking T and U, returning R
() -> void      // Function taking no params, returning nothing

// Pointer types (unsafe)
*T              // Raw pointer to T
*const T        // Immutable raw pointer
*mut T          // Mutable raw pointer
```

#### User-Defined Types

##### Type Aliases
```zen
// Simple alias
type UserId = string;
type Timestamp = i64;

// Generic alias
type Result<T, E> = { ok: bool, data: ?T, error: ?E };
type Map<K, V> = { keys: K[], values: V[] };
```

##### Structures
```zen
// Basic struct - all fields snake_case
struct User {
    user_id: string,
    display_name: string,
    email_address: ?string,
    created_at: Timestamp,
    is_active: bool,
}

// Generic struct
struct Container<T> {
    inner_value: T,
    size_bytes: usize,
}

// Empty struct
struct Marker {}
```

##### Enumerations
```zen
// Simple enum
enum Status {
    Active,
    Inactive,
    Pending,
}

// Enum with associated data
enum ApiError {
    NetworkError(string),              // Tuple variant
    ValidationError { 
        field_name: string, 
        error_code: i32 
    },                                 // Struct variant  
    NotFound,                          // Unit variant
    Timeout,
}

// Enum with explicit discriminant (like C)
enum HttpStatus: u16 {
    Ok = 200,
    NotFound = 404,
    InternalError = 500,
}
```

### Memory Management Semantics

#### Allocation and Deallocation
```zen
// Manual allocation - returns raw pointer
let buffer: *mut u8 = allocate(1024);
defer free(buffer);  // Compiler ensures this runs

// Stack allocation (automatic)
let local_array: [i32; 100] = [0; 100];  // On stack

// Arena allocation (bulk cleanup)
let arena = Arena.new(4096);
defer arena.cleanup();

let ptr1 = arena.allocate(64);
let ptr2 = arena.allocate(128);  // All freed together
```

#### Borrow Checker Light
```zen
// Zen prevents use-after-free without complex lifetime annotations
func safe_reference_usage() {
    let buffer = allocate(1024);
    
    let reference = get_reference(buffer);  // Compiler tracks this
    free(buffer);                           // ERROR: buffer still referenced
    
    use_reference(reference);               // Would be use-after-free
}

// But allows explicit unsafe when needed
func explicit_control() {
    unsafe {
        let buffer = allocate(1024);
        let ptr = buffer;
        free(buffer);
        // Compiler allows this in unsafe block
        write_to_ptr(ptr);  // Your responsibility now
    }
}
```

#### Resource Management with Defer
```zen
// Defer executes in reverse order (LIFO)
func resource_management() -> Result<void, Error> {
    let file = open_file("data.txt")?;
    defer close_file(file);
    
    let buffer = allocate(4096);
    defer free(buffer);
    
    let lock = acquire_lock()?;
    defer release_lock(lock);
    
    // Even if error occurs, all defers execute:
    // 1. release_lock(lock)
    // 2. free(buffer)  
    // 3. close_file(file)
    
    return process_data(file, buffer);
}
```

### Error Handling Semantics

#### Result Types (No Ok/Err Constructors)
```zen
// Functions return success value or throw error
func divide(a: f64, b: f64) -> Result<f64, MathError> {
    if (b == 0.0) throw MathError.DivisionByZero;
    return a / b;  // Automatic Ok() wrapping
}

// Error propagation with ?
func chain_operations() -> Result<f64, MathError> {
    let x = divide(10.0, 2.0)?;  // Propagates error automatically
    let y = divide(x, 3.0)?;
    return y * 2.0;
}
```

#### Pattern Matching on Errors
```zen
// Catch expressions with pattern matching
let result = risky_operation() catch {
    NetworkError(msg) => {
        log_error(msg);
        throw UserError.ConnectionFailed;
    },
    TimeoutError => return "timeout_fallback",
    ValidationError { field_name, error_code } => {
        return `Invalid ${field_name}: code ${error_code}`;
    },
};

// Try-else for simple fallbacks
let value = try parse_number(input) else 0;
let user = try fetch_user(id) else User.default();
```

### Function and Control Flow

#### Function Declaration
```zen
// Basic function
func add(a: i32, b: i32) -> i32 {
    return a + b;
}

// Function with multiple return types
func divide_safe(a: i32, b: i32) -> Result<i32, string> {
    if (b == 0) throw "division by zero";
    return a / b;
}

// Generic function
func swap<T>(a: *mut T, b: *mut T) -> void {
    let temp = *a;
    *a = *b;
    *b = temp;
}

// Function with default parameters
func greet(name: string, prefix: string = "Hello") -> string {
    return `${prefix}, ${name}!`;
}
```

#### Control Flow Constructs
```zen
// If expressions (return values)
let result = if (condition) {
    "success"
} else {
    "failure"
};

// For loops
for (item in collection) {
    process(item);
}

for (i in 0..10) {           // Range 0 to 9
    print(i);
}

for (i in 0...10) {          // Range 0 to 10 (inclusive)
    print(i);
}

// While loops
while (has_more_data()) {
    process_next();
}

// Switch expressions with exhaustive checking
let message = switch status {
    case Status.Active: "User is active",
    case Status.Inactive: "User is inactive", 
    case Status.Pending: "User is pending",
    // Compiler ensures all variants handled
};

// Switch with guards
let category = switch age {
    case x if x < 13: "child",
    case x if x < 20: "teenager",
    case x if x < 65: "adult",
    default: "senior",
};
```

### Advanced Features

#### Async/Await
```zen
// Async function declaration
func fetch_data(url: string) -> async Result<string, HttpError> {
    let response = await http.get(url)?;
    return response.body;
}

// Concurrent execution
func fetch_multiple(urls: string[]) -> async string[] {
    let futures = urls.map(|url| async fetch_data(url));
    let results = await Promise.all(futures);
    return results.filter_ok();
}

// Spawning background tasks
func background_processing() -> void {
    spawn async {
        while (true) {
            await process_queue();
            await sleep(1000);
        }
    };
}
```

#### Compile-time Evaluation
```zen
// Compile-time constants
const PI: f64 = 3.14159265359;
const MAX_USERS: i32 = comptime calculate_max_users();

// Compile-time function execution
func calculate_fibonacci(n: i32) -> comptime i32 {
    if (n <= 1) return n;
    return calculate_fibonacci(n - 1) + calculate_fibonacci(n - 2);
}

const FIB_10: i32 = comptime calculate_fibonacci(10);  // Evaluated at compile time
```

#### Unsafe Operations
```zen
// Unsafe blocks for low-level operations
func fast_memory_copy(dest: *mut u8, src: *const u8, len: usize) -> void {
    unsafe {
        // Direct memory manipulation
        for (i in 0..len) {
            *(dest + i) = *(src + i);
        }
    }
}

// Calling C functions
extern "C" func malloc(size: usize) -> *mut void;
extern "C" func free(ptr: *mut void) -> void;

func c_malloc_wrapper(size: usize) -> *mut u8 {
    unsafe {
        return malloc(size) as *mut u8;
    }
}
```

---

*Zen: Powerful by design, simple by choice.*
