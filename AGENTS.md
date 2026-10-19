# Retrofeed

A web app for subscribing to blogs and reading their articles with a nice reading-view.

## MCPs

- chrome-devtools

## Development
```bash
bin/setup                         # Initial setup
bin/dev                           # Start server (port 3006)
bin/rails test                    # Unit tests
bin/rails test:e2e                # End-to-end tests
bin/rails test:system             # System tests
bin/ci                            # Full CI (Rubocop, Brakeman, tests)
bin/rails db:fixtures:load        # Load fixtures
bin/rails db:reset                # Reset database
```

URL: http://retrofeed.localhost:3006
Login: admin@retrofeed.com / password123

## Coding Rules

Also see @STYLE.md

### General
- No emoji in code, output, or comments
- Write informative comments that explain intent without requiring deep code reading

### Conditionals
- Prefer expanded `if/else` over guard clauses
- Guard clauses OK at method start when main body is non-trivial

### Method Ordering
1. Class methods
2. Public methods (`initialize` first)
3. Private methods
m
Order by invocation—callers above callees.

### Visibility Modifiers
No newline after `private`; indent content beneath it.
```ruby
private
    def helper
    end
```

### Controllers
- Model endpoints as CRUD on resources (REST)
- New resource > custom action
- Thin controllers, rich models
- Call Active Record or intention-revealing model methods directly

### Components
- Prever views and html+classes over view components

### Async Operations
- `_later` suffix = enqueues job
- `_now` suffix = synchronous execution

### Testing
- For each new feature try to include some testing coverage
- Failing tests are not acceptable
- Always run the test suite, to make sure you didn't break anything

### ERB
- Prefer pure html implementations, using classes
- SVGs must be reusable components, never inline

### Styling
- Prefer using modern CSS. Style rules are separated in different files. Use BEM convention for naming.
- Make CSS reusable, use CSS theme where possible.
- Always include `dark:` variants for colors.
