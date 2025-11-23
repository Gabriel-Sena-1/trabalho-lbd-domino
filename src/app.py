from conexao.banco import conectar_banco
from funcoes.funcoes_banco import comprar_peca, detectar_jogo_trancado, jogar_peca, listar_jogadas_possiveis, listar_partidas_com_vencedores, listar_ranking_jogadores
from funcoes.menu import menu
    
def main():
    connection = conectar_banco()
    
    if not connection:
        print("Não foi possível conectar ao banco de dados. Encerrando...")
        return
    
    print("Conexão estabelecida com sucesso!")
    
    while True:
        opcao = menu()
        
        if opcao == "1":
            listar_ranking_jogadores(connection)
        elif opcao == "2":
            listar_partidas_com_vencedores(connection)
        elif opcao == "3":
            id_jogador = input("Digite o id do Jogador: ")
            id_peca = input("Digite o id da Partida: ")
            comprar_peca(connection, id_jogador, id_peca)
        elif opcao == "4":
            id_jogador = input("Digite o id do Jogador: ")
            id_partida = input("Digite o id da Partida: ")
            id_peca = input("Digite o id da Peça: ")
            id_lado_mesa = input("Digite o lado da mesa (1 para direito | 2 para esquerdo): ")
            jogar_peca(connection, id_jogador, id_partida, id_peca, id_lado_mesa)
        elif opcao == "5":
            id_jogador = input("Digite o id do Jogador: ")
            id_partida = input("Digite o id da Partida: ")
            listar_jogadas_possiveis(connection, id_jogador, id_partida)
        elif opcao == "6":
            id_partida = input("Digite o id da Partida: ")
            result = detectar_jogo_trancado(connection, id_partida)
            if result is not None:
              print(f"O Jogo ainda não está trancado!")

        elif opcao == "0":
            print("Encerrando...")
            break
        else:
            print("Opção inválida! Tente novamente.")
    
    if connection:
        connection.close()
        print("Conexão fechada.")

if __name__ == "__main__":
    main()
