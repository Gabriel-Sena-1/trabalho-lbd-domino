from conexao.banco import conectar_banco
from funcoes.funcoes_banco import comprar_peca, detectar_jogo_trancado, jogar_peca, limpar_dados, listar_jogadas_possiveis, listar_partidas_com_vencedores, listar_ranking_jogadores
from funcoes.menu import menu, menu_insercao
from funcoes.insercoes_banco import inserir_dupla, inserir_jogador, inserir_jogo, inserir_partida, inserir_peca_domino, listar_dupla_por_id, listar_duplas, listar_jogadores, listar_jogos, vincular_jogador_dupla
    
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
        elif opcao.upper() == "A":
            while True:
                opcao_menu = menu_insercao()
                if opcao_menu == "1":
                    lado_a = input("Digite o valor do lado A da peça: ")
                    lado_b = input("Digite o valor do lado B da peça: ")
                    inserir_peca_domino(connection, lado_a, lado_b)
                elif opcao_menu == "2":
                    nome = input("Digite o nome do jogador: ")
                    email = input("Digite o email do jogador: ")
                    inserir_jogador(connection, nome, email)
                elif opcao_menu == "3":
                    nome_jogo = input("Digite o nome do jogo: ")
                    tipo_jogo = input("Digite o tipo do jogo (2, 3 ou 4 jogadores): ")
                    inserir_jogo(connection, nome_jogo, tipo_jogo)
                elif opcao_menu == "4":
                    nome_dupla = input("Digite o nome da dupla: ")
                    inserir_dupla(connection, nome_dupla)
                elif opcao_menu == "5":
                    listar_jogos(connection)
                    id_jogo = input("Digite o ID do jogo: ")
                    numero = input("Digite o número da partida: ")
                    inserir_partida(connection, id_jogo, numero)
                elif opcao_menu == "6":
                    listar_duplas(connection)
                    listar_jogadores(connection)
                    id_dupla = input("Digite o ID da dupla: ")
                    id_jogador = input("Digite o ID do jogador: ")
                    vincular_jogador_dupla(connection, id_dupla, id_jogador)
                elif opcao_menu == "7":
                    id_dupla = input("Digite o ID da dupla: ")
                    listar_dupla_por_id(connection, id_dupla)
                elif opcao_menu == "8":
                    confirmar = input("Tem certeza que deseja limpar todos os dados? (s/n): ")
                    if confirmar.lower() == "s":
                        limpar_dados(connection)
                        print("Dados limpos com sucesso!")
                    else:
                        print("Operação de limpeza cancelada.")

                elif opcao_menu == "0":
                    break
                else:
                    print("Opção inválida no menu de inserção! Tente novamente.")
                

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
