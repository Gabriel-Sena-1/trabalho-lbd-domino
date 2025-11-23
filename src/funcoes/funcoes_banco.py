from psycopg2 import Error

def listar_ranking_jogadores(connection):
    try:
        cursor = connection.cursor()
        cursor.execute("SELECT * FROM public.vw_ranking_jogadores")
        pecas = cursor.fetchall()

        if pecas:
            print("\n=== Ranking de Jogadores ===")
            i = 1
            for peca in pecas:
                print(f"{i}. JOGADOR: {peca[0]} | PARTIDAS GANHAS: {peca[1]} | JOGOS GANHOS: {peca[2]}")
                i += 1
        else:
            print("Nenhuma peça encontrada.")
        
        cursor.close()
    except Error as e:
        print(f"Erro ao listar usuários: {e}")

def listar_jogadas_possiveis(connection, id_jogador, id_partida):
    try:
        cursor = connection.cursor()
        cursor.execute("SELECT * FROM public.jogadas_possiveis(%s, %s);", (id_jogador, id_partida))
        jogadas = cursor.fetchall()
        
        if jogadas:
            print(f"\n=== Jogadas possíveis para o jogador {id_jogador} na partida {id_partida} ===")
            for jogada in jogadas:
                print(f"ID da PEÇA: {jogada[0]}")
        else:
            print("Nenhuma jogada encontrada.")
        
        cursor.close()
    except Error as e:
        print(f"Erro ao listar duplas: {e}")

def listar_partidas_com_vencedores(connection):
    try:
        cursor = connection.cursor()
        cursor.execute("SELECT * FROM public.vw_lista_partidas_vencedores")
        partidas = cursor.fetchall()
        
        if partidas:
            print("\n=== Partidas ===")
            i = 1
            for partida in partidas:
                print(f"{i}. ID PARTIDA: {partida[0]} | ID JOGO: {partida[1]} | NÚMERO: {partida[2]} | VENCEDOR DUPLA ID: {partida[3]} | VENCEDOR DUPLA NOME: {partida[7]}")
                i += 1
        else:
            print("Nenhuma partida encontrada.")
        
        cursor.close()
    except Error as e:
        print(f"Erro ao listar partidas: {e}")

def comprar_peca(connection, id_jogador, id_partida):
    try:
        cursor = connection.cursor()
        query = "CALL public.comprar_peca(%s, %s);"
        cursor.execute(query, (id_jogador, id_partida))
        connection.commit()
        print(f"Peça comprada com sucesso pelo jogador '{id_jogador}'!")
        cursor.close()
    except Error as e:
        print(e)
        connection.rollback()

def jogar_peca(connection, id_jogador, id_partida, id_peca, lado_mesa):
    try:
        cursor = connection.cursor()
        query = "CALL public.jogar_peca(%s, %s, %s, %s);"
        cursor.execute(query, (id_jogador, id_partida, id_peca, lado_mesa))
        connection.commit()
        
        # Captura e exibe as mensagens NOTICE do PostgreSQL
        for notice in connection.notices:
            print(notice.strip())
        connection.notices.clear()
        
        print(f"Peça jogada com sucesso pelo jogador '{id_jogador}' na partida '{id_partida}'!")
        cursor.close()
    except Error as e:
        print(e)
        connection.rollback()
        cursor.close()

def detectar_jogo_trancado(connection, id_partida):
    try:
        cursor = connection.cursor()
        cursor.execute("SELECT * FROM detectar_jogo_trancado(%s);", (id_partida,))
        resultado = cursor.fetchone()
        cursor.close()
        return resultado[0]
    except Error as e:
        print(e)
        cursor.close()
        return None