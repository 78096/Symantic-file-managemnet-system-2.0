import json
import hashlib
import os

USERS_FILE = ".users.json"

def hash_password(password):
    # Same hashing as your bash script uses: sha256 hex digest
    return hashlib.sha256(password.encode("utf-8")).hexdigest()

def create_admin_user(username, password):
    user = {
        "username": username,
        "password": hash_password(password),
        "role": "admin",
        "permissions": ["list_files", "create_file", "delete_file", "move_file", "read_file"]
    }
    return user

def reset_users_file():
    admin_username = "Methembe"
    admin_password = "1111"

    users_data = {
        "users": [
            create_admin_user(admin_username, admin_password)
        ]
    }

    with open(USERS_FILE, "w") as f:
        json.dump(users_data, f, indent=2)
    print(f"Reset {USERS_FILE} and created admin user '{admin_username}' with password '{admin_password}'")

if __name__ == "__main__":
    reset_users_file()
