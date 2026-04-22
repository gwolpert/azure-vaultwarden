import argon2, os, json

token = os.environ['ADMIN_TOKEN']

# Skip hashing if the token is already an argon2 PHC string
if token.startswith('$argon2'):
    hashed = token
else:
    hasher = argon2.PasswordHasher(
        time_cost=3,
        memory_cost=65536,
        parallelism=4,
        type=argon2.Type.ID
    )
    hashed = hasher.hash(token)

with open(os.environ['AZ_SCRIPTS_OUTPUT_PATH'], 'w') as f:
    json.dump({'hashedToken': hashed}, f)
