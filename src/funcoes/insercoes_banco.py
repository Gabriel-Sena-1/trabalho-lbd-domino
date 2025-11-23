from psycopg2 import Error

def inserir_peca_domino(connection, lado_a, lado_b):
    try:
        cursor = connection.cursor()
        query = "INSERT INTO peca_domino(lado_a, lado_b) VALUES (%s, %s);"
        cursor.execute(query, (lado_a, lado_b))
        connection.commit()
        print(f"Peça [{lado_a}|{lado_b}] inserida com sucesso!")
        cursor.close()
    except Error as e:
        print(f"Erro ao inserir peça: {e}")
        connection.rollback()
        cursor.close()

def inserir_jogador(connection, nome, email):
    try:
        cursor = connection.cursor()
        query = "INSERT INTO jogador(nome, email) VALUES (%s, %s);"
        cursor.execute(query, (nome, email))
        connection.commit()
        print(f"Jogador '{nome}' inserido com sucesso!")
        cursor.close()
    except Error as e:
        print(f"Erro ao inserir jogador: {e}")
        connection.rollback()
        cursor.close()

def inserir_jogo(connection, nome_jogo, tipo_jogo):
    try:
        cursor = connection.cursor()
        query = "INSERT INTO jogo(nome_jogo, tipo_jogo) VALUES (%s, %s);"
        cursor.execute(query, (nome_jogo, tipo_jogo))
        connection.commit()
        print(f"Jogo '{nome_jogo}' do tipo {tipo_jogo} inserido com sucesso!")
        cursor.close()
    except Error as e:
        print(f"Erro ao inserir jogo: {e}")
        connection.rollback()
        cursor.close()

def inserir_dupla(connection, nome_dupla):
    try:
        cursor = connection.cursor()
        query = "INSERT INTO dupla(nome_dupla) VALUES (%s);"
        cursor.execute(query, (nome_dupla,))
        connection.commit()
        print(f"Dupla '{nome_dupla}' inserida com sucesso!")
        cursor.close()
    except Error as e:
        print(f"Erro ao inserir dupla: {e}")
        connection.rollback()
        cursor.close()

def inserir_partida(connection, id_jogo, numero):
    try:
        cursor = connection.cursor()
        query = "INSERT INTO partida(id_jogo, numero) VALUES (%s, %s);"
        cursor.execute(query, (id_jogo, numero))
        connection.commit()
        print(f"Partida número {numero} do jogo {id_jogo} inserida com sucesso!")
        cursor.close()
    except Error as e:
        print(f"Erro ao inserir partida: {e}")
        connection.rollback()
        cursor.close()

def listar_duplas(connection):
    try:
        cursor = connection.cursor()
        query = "SELECT id_dupla, nome_dupla FROM dupla;"
        cursor.execute(query)
        duplas = cursor.fetchall()
        
        if duplas:
            print("Duplas cadastradas:")
            for dupla in duplas:
                print(f"ID: {dupla[0]}, Nome: {dupla[1]}")
        else:
            print("Nenhuma dupla encontrada.")
        
        cursor.close()
    except Error as e:
        print(f"Erro ao listar duplas: {e}")

def listar_jogadores(connection):
    try:
        cursor = connection.cursor()
        query = "SELECT id_jogador, nome, email FROM jogador;"
        cursor.execute(query)
        jogadores = cursor.fetchall()
        
        if jogadores:
            print("Jogadores cadastrados:")
            for jogador in jogadores:
                print(f"ID: {jogador[0]}, Nome: {jogador[1]}, Email: {jogador[2]}")
        else:
            print("Nenhum jogador encontrado.")
        
        cursor.close()
    except Error as e:
        print(f"Erro ao listar jogadores: {e}")

def listar_jogos(connection):
    try:
        cursor = connection.cursor()
        query = "SELECT id_jogo, nome_jogo, tipo_jogo, criado_em FROM jogo;"
        cursor.execute(query)
        jogos = cursor.fetchall()
        
        if jogos:
            print("Jogos cadastrados:")
            for jogo in jogos:
                print(f"ID: {jogo[0]}, Nome: {jogo[1]}, Tipo: {jogo[2]}, Criado em: {jogo[3]}")
        else:
            print("Nenhum jogo encontrado.")
        
        cursor.close()
    except Error as e:
        print(f"Erro ao listar jogos: {e}")
      

def listar_dupla_por_id(connection, id_dupla):
    try:
        cursor = connection.cursor()
        query = "SELECT * FROM f_lista_jogadores_por_id_dupla(%s);"
        cursor.execute(query, (id_dupla,))
        duplas = cursor.fetchall()
        
        for jogador in duplas:
            print(f"ID JOGADOR: {jogador[0]} | NOME: {jogador[1]} | EMAIL: {jogador[2]}")
        
        cursor.close()
    except Error as e:
        print(f"Erro ao listar dupla por ID: {e}")

def vincular_jogador_dupla(connection, id_dupla, id_jogador):
    try:
        cursor = connection.cursor()
        query = "INSERT INTO jogador_dupla(id_dupla, id_jogador) VALUES (%s, %s);"
        cursor.execute(query, (id_dupla, id_jogador))
        connection.commit()
        print(f"Jogador {id_jogador} vinculado à dupla {id_dupla} com sucesso!")
        cursor.close()
    except Error as e:
        print(f"Erro ao vincular jogador à dupla: {e}")
        connection.rollback()
        cursor.close()
