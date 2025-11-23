# Sistema de Gerenciamento de Jogo de Dominó

Este projeto implementa um sistema completo de gerenciamento de jogos de dominó, onde **toda a lógica do domínio está implementada no banco de dados PostgreSQL** através de procedures, functions, triggers e views.

## 📋 Sobre o Projeto

A aplicação Python serve apenas como interface para executar queries e exibir resultados. Toda a lógica de negócio do jogo de dominó (validações, regras, pontuação, detecção de jogo trancado, etc.) está implementada diretamente no PostgreSQL usando:

- **Procedures**: Comprar peça do monte, validar jogada;
- **Functions**: Verificar jogadas possíveis, detectar jogo trancado;
- **Triggers**:  Calcular pontos automaticamente ao bater/fechar;
- **Views**: Ranking de pontuação (por usuário), contando quantas partidas vencidas e quantos
jogos vencidos, Listagem de cada partida e seu vencedor.

## 🚀 Como Executar

### 1. Rodar o Docker

O dump completo do banco de dados será carregado automaticamente ao iniciar o container:

```bash
docker-compose up -d
```

Isso irá:

- Subir o PostgreSQL na porta `5433`
- Carregar automaticamente o arquivo `entrypoint/database.sql` com toda a estrutura, dados e lógica
- Subir o pgAdmin na porta `8090` (opcional)

### 2. Ativar o Ambiente Virtual Python

```bash
python -m venv .venv
source .venv/bin/activate  # No Linux/Mac
# ou
.venv\Scripts\activate  # No Windows
```

### 3. Instalar Dependências

```bash
pip install -r requirements.txt
```

### 4. Rodar o Programa

```bash
python src/app.py
```

## 🎮 Funcionalidades

O programa oferece um menu interativo com as seguintes opções:

1. **Lista ranking de jogadores** - Visualiza o ranking baseado em vitórias
2. **Listar partidas com vencedores** - Mostra histórico de partidas
3. **Comprar peça** - Jogador compra uma peça do monte
4. **Jogar peça** - Executa uma jogada (com validação automática de regras)
5. **Listar jogadas possíveis** - Mostra quais peças o jogador pode jogar
6. **Detectar jogo trancado** - Verifica se o jogo está trancado

## 🗄️ Estrutura do Projeto

```
.
├── docker-compose.yml          # Configuração do Docker
├── entrypoint/
│   └── database.sql            # Dump completo do banco (carregado automaticamente)
├── src/
│   ├── app.py                  # Interface Python
│   └── conexao/
│       └── banco.py            # Conexão com PostgreSQL
│   └── funcoes/
│       └── funcoes_banco.py    # Funções que chamam comandos SQL
│       └── menu.py             # Função que exibe o menu e capta resposta do usuário
├── requirements.txt            # Dependências Python (psycopg2)
└── README.md
```