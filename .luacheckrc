globals = {
    "box",
    "_TARANTOOL",
}

ignore = {
    -- Shadowing an upvalue argument.
    "432",
}

include_files = {
    '.luacheckrc',
    '*.rockspec',
    '**/*.lua',
}

exclude_files = {
    '.rocks',
}
