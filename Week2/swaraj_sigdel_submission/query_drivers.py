# Week 2 Assignment — Swaraj Sigdel
# Python: connect to PostgreSQL and run the completed-rides-per-driver query
# Credentials are loaded from a .env file (never hardcode passwords)

import psycopg2
import os
from dotenv import load_dotenv

# Load database credentials from .env
load_dotenv()

host = os.getenv("DB_HOST")
port = os.getenv("DB_PORT")
dbname = os.getenv("DB_NAME")
user = os.getenv("DB_USER")
password = os.getenv("DB_PASSWORD")

# Open a connection to the database
conn = psycopg2.connect(
    host=host, port=port, dbname=dbname, user=user, password=password
)

cur = conn.cursor()

# Query: completed rides per driver, most active first
sql = '''
    SELECT d.name, COUNT(*)
    FROM drivers d
    JOIN trips t ON d.driver_id = t.driver_id
    WHERE t.status = 'completed'
    GROUP BY d.name
    ORDER BY COUNT(*) DESC;
'''

cur.execute(sql)

# Fetch all rows and print them in a clean aligned format
rows = cur.fetchall()
for name, count in rows:
    print(f"{name:<25} {count:>10}")

# Always close the cursor and connection when done
cur.close()
conn.close()