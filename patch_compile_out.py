import sys, re

with open(sys.argv[1], 'r', encoding='utf-8', errors='replace') as f:
    content = f.read()

# Remove broken static _krlam* functions (ones with duplicate params)
# Pattern: static char* _krlam\d+(... duplicate params ...) {
def remove_krlam_funcs(c):
    # Find all _krlam function definitions and check for dups
    result = []
    i = 0
    while i < len(c):
        # Look for static char* _krlam
        m = c.find("static char* _krlam", i)
        if m < 0:
            result.append(c[i:])
            break
        result.append(c[i:m])
        # Find the end of this function
        depth = 0
        j = m
        in_str = False
        while j < len(c):
            if not in_str and c[j] == "{": depth += 1
            elif not in_str and c[j] == "}":
                depth -= 1
                if depth == 0:
                    j += 1
                    break
            elif c[j] == "\"" and j > 0 and c[j-1] != "\\": in_str = not in_str
            j += 1
        func_text = c[m:j]
        # Check for duplicate params (sign of broken lambda)
        # Extract param list
        paren = func_text.find("(")
        paren_end = func_text.find(")", paren)
        if paren >= 0 and paren_end >= 0:
            params_str = func_text[paren+1:paren_end]
            params = [p.strip().split()[-1] for p in params_str.split(",") if p.strip()]
            if len(params) != len(set(params)):
                # Broken lambda - replace with empty stub
                fname = func_text[len("static char* "):func_text.find("(")]
                result.append(f"/* removed broken {fname} */\n")
                print(f"Removed broken: {fname}")
            else:
                result.append(func_text)
        else:
            result.append(func_text)
        i = j
    return "".join(result)

content = remove_krlam_funcs(content)

with open(sys.argv[2], "w", encoding="utf-8") as f:
    f.write(content)
print("Patch complete")
