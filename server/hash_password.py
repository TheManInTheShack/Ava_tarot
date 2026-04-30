"""One-off helper: print a bcrypt hash for a given password."""
import sys
import bcrypt

if len(sys.argv) != 2:
    print("usage: python hash_password.py <password>")
    sys.exit(1)

hashed = bcrypt.hashpw(sys.argv[1].encode(), bcrypt.gensalt())
print(hashed.decode())
