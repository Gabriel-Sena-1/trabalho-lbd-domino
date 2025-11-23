import psycopg2
from psycopg2 import Error

def conectar_banco():
    """Conecta ao banco de dados PostgreSQL"""
    try:
        connection = psycopg2.connect(
            host="localhost",
            port="5433",
            database="postgres",
            user="postgres",
            password="minhasenha"
        )
        return connection
    except Error as e:
        print(f"Erro ao conectar ao banco de dados: {e}")
        return None