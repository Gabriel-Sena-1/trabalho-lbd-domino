# Documentação - Sistema de Gerenciamento de Jogo de Dominó

## Principais Consultas, Funções e Gatilhos SQL

Este documento apresenta as principais estruturas SQL implementadas no sistema e os problemas que elas resolvem.

---

## 1. PROCEDURES (Procedimentos Armazenados)

### 1.1 Comprar Peça (Procedure)

**Problema que resolve:** Permite que um jogador compre uma peça do monte durante a partida, garantindo atomicidade na transação e validando se o jogador pertence à partida.

**Validações implementadas:**

- Verifica se o jogador pertence à partida através de JOINs entre as tabelas `jogador`, `jogador_jogo`, `jogo` e `partida`
- Garante que apenas uma transação pegue a mesma peça usando `FOR UPDATE` (evita condições de corrida)
- Valida se o monte não está vazio
- Remove a peça do monte e adiciona na mão do jogador de forma atômica

```sql
CREATE PROCEDURE public.comprar_peca(IN p_jogador integer, IN p_partida integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    p_id_peca INT;
    v_jogador_pertence BOOLEAN;
BEGIN
    -- 1. VERIFICA SE O JOGADOR PERTENCE À PARTIDA
    SELECT EXISTS (
        SELECT 1
        FROM jogador j
        JOIN jogador_jogo jj ON j.id_jogador = jj.id_jogador
        JOIN jogo jo ON jj.id_jogo = jo.id_jogo
        JOIN partida p ON p.id_jogo = jo.id_jogo
        WHERE j.id_jogador = p_jogador
          AND p.id_partida = p_partida
    ) INTO v_jogador_pertence;

    IF NOT v_jogador_pertence THEN
        RAISE EXCEPTION 'Erro de Regra: Jogador ID % nao pertence a partida ID %.', p_jogador, p_partida;
    END IF;

    -- 2. Pega a primeira peca disponivel no monte (a de menor ordem)
    SELECT id_peca INTO p_id_peca
    FROM monte
    WHERE id_partida = p_partida
    ORDER BY ordem
    LIMIT 1
    FOR UPDATE; -- Garante que so uma transacao pegue esta peca

    -- 3. Verifica se o monte esta vazio
    IF p_id_peca IS NULL THEN
        RAISE EXCEPTION 'Monte vazio. Nao foi possivel comprar peca.';
    END IF;

    -- 4. Remove do monte (usando o id_peca para ser simples)
    DELETE FROM monte
    WHERE id_peca = p_id_peca AND id_partida = p_partida;

    -- 5. Coloca na mao do jogador
    INSERT INTO mao (id_partida, id_jogador, id_peca)
    VALUES (p_partida, p_jogador, p_id_peca);
END;
$$;
```

---

### 1.2 Jogar Peça (Procedure)

**Problema que resolve:** Executa uma jogada completa no dominó, validando todas as regras do jogo e atualizando o estado da partida automaticamente.

**Validações e ações implementadas:**

- Verifica se o jogador possui a peça na mão
- Valida se a peça combina com as pontas atuais da mesa (regras do dominó)
- Diferencia primeira jogada das jogadas subsequentes
- Atualiza automaticamente as pontas da partida após a jogada
- Passa o turno para o próximo jogador
- Registra a jogada no histórico
- Remove a peça da mão do jogador (acionando o trigger de verificação de fim de partida)

```sql
CREATE PROCEDURE public.jogar_peca(IN p_jogador integer, IN p_partida integer, IN p_peca integer, IN p_lado_mesa integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_mao_id INT;
    v_lado_a_peca INT;
    v_lado_b_peca INT;
    v_ponta_a INT;
    v_ponta_b INT;
    v_ordem_jogada INT;
    v_pecas_na_mesa INT;

BEGIN
    -- 1. VERIFICA SE O JOGADOR TEM A PECA NA MAO
    SELECT id_mao INTO v_mao_id
    FROM mao
    WHERE id_jogador = p_jogador
      AND id_partida = p_partida
      AND id_peca = p_peca;

    IF v_mao_id IS NULL THEN
        RAISE EXCEPTION 'Erro de Regra: Jogador nao possui a peca ID %.', p_peca;
    END IF;

    -- 2. OBTER VALORES DA PECA
    SELECT lado_a, lado_b INTO v_lado_a_peca, v_lado_b_peca
    FROM peca_domino
    WHERE id_peca = p_peca;

    -- 3. OBTER ESTADO ATUAL DA MESA (PONTAS E CONTAGEM DE PECAS)
    SELECT COALESCE(COUNT(*), 0) INTO v_pecas_na_mesa
    FROM peca_jogada
    WHERE id_partida = p_partida;

    SELECT ponta_a, ponta_b INTO v_ponta_a, v_ponta_b
    FROM partida
    WHERE id_partida = p_partida;

    -----------------------------------------------------
    -- LOGICA DE REGRA DO DOMINO
    -----------------------------------------------------

    IF v_pecas_na_mesa = 0 THEN
        -- Primeira jogada (Apenas para simplificacao: qualquer peca e aceita)

        -- A nova ponta A sera o lado menor, e a nova ponta B sera o lado maior.
        v_ponta_a := LEAST(v_lado_a_peca, v_lado_b_peca);
        v_ponta_b := GREATEST(v_lado_a_peca, v_lado_b_peca);

        -- Define a ordem de jogada
        v_ordem_jogada := 1;

    ELSE
        -- Jogadas subsequentes (a peca deve conectar a uma das pontas)

        DECLARE
            v_ponta_a_antiga INT := v_ponta_a;
            v_ponta_b_antiga INT := v_ponta_b;
            v_peca_combina BOOLEAN := FALSE;
        BEGIN

            IF p_lado_mesa = 1 THEN -- Tenta jogar na Ponta A (v_ponta_a_antiga)

                IF v_lado_a_peca = v_ponta_a_antiga THEN
                    v_ponta_a := v_lado_b_peca;
                    v_peca_combina := TRUE;
                ELSIF v_lado_b_peca = v_ponta_a_antiga THEN
                    v_ponta_a := v_lado_a_peca;
                    v_peca_combina := TRUE;
                END IF;

                IF NOT v_peca_combina THEN
                    RAISE EXCEPTION 'Erro de Regra: A peca [%|%] nao combina com a Ponta A (%).', v_lado_a_peca, v_lado_b_peca, v_ponta_a_antiga;
                END IF;

            ELSIF p_lado_mesa = 2 THEN -- Tenta jogar na Ponta B (v_ponta_b_antiga)

                IF v_lado_a_peca = v_ponta_b_antiga THEN
                    v_ponta_b := v_lado_b_peca;
                    v_peca_combina := TRUE;
                ELSIF v_lado_b_peca = v_ponta_b_antiga THEN
                    v_ponta_b := v_lado_a_peca;
                    v_peca_combina := TRUE;
                END IF;

                IF NOT v_peca_combina THEN
                    RAISE EXCEPTION 'Erro de Regra: A peca [%|%] nao combina com a Ponta B (%).', v_lado_a_peca, v_lado_b_peca, v_ponta_b_antiga;
                END IF;

            ELSE
                RAISE EXCEPTION 'Erro de Entrada: Lado da mesa invalido (use 1 para A ou 2 para B).';
            END IF;

        END;

        -- Determinar a ordem de jogada
        SELECT COALESCE(MAX(ordem_jogada), 0) + 1 INTO v_ordem_jogada
        FROM peca_jogada
        WHERE id_partida = p_partida;

    END IF;

    -----------------------------------------------------
    -- EXECUCAO DA JOGADA (Se as regras foram atendidas)
    -----------------------------------------------------

    -- 4. REMOVE DA MAO
    DELETE FROM mao WHERE id_mao = v_mao_id;

    -- 5. INSERE NA MESA (CORRIGIDO: usa lado_jogada no INSERT)
    INSERT INTO peca_jogada (id_partida, id_peca, id_jogador, ordem_jogada, lado_jogada)
    VALUES (p_partida, p_peca, p_jogador, v_ordem_jogada, p_lado_mesa);

    -- 6. ATUALIZA AS PONTAS DA PARTIDA E PASSA O TURNO
    UPDATE partida
    SET ponta_a = v_ponta_a,
        ponta_b = v_ponta_b,
        -- Logica para passar para o proximo jogador.
        vez_do_jogador = (
            SELECT id_jogador
            FROM jogador_jogo jj
            WHERE jj.id_jogo = (SELECT id_jogo FROM partida WHERE id_partida = p_partida)
            AND jj.id_jogador != p_jogador -- Pega um jogador diferente do atual
            ORDER BY jj.posicao -- assume que o proximo e o da proxima posicao
            LIMIT 1
        )
    WHERE id_partida = p_partida;

    -- 7. REGISTRA A JOGADA NO HISTORICO
    INSERT INTO jogada (id_partida, id_jogador, id_peca, tipo)
    VALUES (p_partida, p_jogador, p_peca, 'Jogada');

END;
$$;
```

---

## 2. FUNCTIONS (Funções)

### 2.1 Detectar Jogo Trancado (Function)

**Problema que resolve:** Verifica automaticamente se o jogo está em estado de "trancamento" (quando nenhum jogador pode fazer uma jogada válida).

**Lógica implementada:**

- Obtém as pontas atuais da partida
- Verifica se existe pelo menos uma peça na mão de algum jogador que combine com as pontas
- Retorna FALSE se o jogo não está trancado
- Lança EXCEPTION se o jogo está trancado (permite tratamento pelo trigger)

```sql
CREATE FUNCTION public.detectar_jogo_trancado(p_partida integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_ponta_a INT;
    v_ponta_b INT;
    v_algum_jogador_pode_jogar BOOLEAN;
BEGIN
    -- Seleciona as pontas da partida
    SELECT ponta_a, ponta_b INTO v_ponta_a, v_ponta_b
    FROM partida
    WHERE id_partida = p_partida;

    -- Verifica se ao menos um jogador pode jogar
    SELECT EXISTS (
        SELECT 1
        FROM mao m
        JOIN peca_domino pd ON m.id_peca = pd.id_peca
        WHERE m.id_partida = p_partida
          AND (
              -- Se pontas são NULL (primeira jogada), qualquer peça pode jogar
              v_ponta_a IS NULL
              OR v_ponta_b IS NULL
              -- Ou a peça combina com alguma ponta
              OR pd.lado_a = v_ponta_a
              OR pd.lado_b = v_ponta_a
              OR pd.lado_a = v_ponta_b
              OR pd.lado_b = v_ponta_b
          )
    ) INTO v_algum_jogador_pode_jogar;

    -- Se nenhum jogador pode jogar, jogo está trancado
    IF NOT v_algum_jogador_pode_jogar THEN
        RAISE EXCEPTION 'JOGO TRANCADO: Nenhum jogador pode jogar na partida ID %.', p_partida;
    END IF;

    -- Jogo não está trancado
    RETURN FALSE;
END;
$$;
```

---

### 2.2 Analisar Jogadas Possíveis (Function)

**Problema que resolve:** Retorna todas as peças que um jogador pode jogar no momento, facilitando a interface do usuário e evitando jogadas inválidas.

**Lógica implementada:**

- Obtém as pontas atuais da mesa
- Filtra apenas as peças na mão do jogador que combinam com pelo menos uma das pontas
- Retorna uma tabela com os IDs das peças jogáveis
- Considera o caso especial da primeira jogada (quando pontas são NULL)

```sql
CREATE FUNCTION public.jogadas_possiveis(p_jogador integer, p_partida integer) RETURNS TABLE(id_peca integer, lado_a integer, lado_b integer, pode_jogar_ponta_a boolean, pode_jogar_ponta_b boolean)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_ponta_a INT;
    v_ponta_b INT;
BEGIN
    -- Seleciona as pontas da partida
    SELECT ponta_a, ponta_b INTO v_ponta_a, v_ponta_b
    FROM partida
    WHERE id_partida = p_partida;

    -- Retorna as peças da mão do jogador que podem ser jogadas
    RETURN QUERY
    SELECT
        pd.id_peca,
        pd.lado_a,
        pd.lado_b,
        -- Verifica se a peça pode ser jogada na ponta A
        (v_ponta_a IS NULL OR pd.lado_a = v_ponta_a OR pd.lado_b = v_ponta_a) AS pode_jogar_ponta_a,
        -- Verifica se a peça pode ser jogada na ponta B
        (v_ponta_b IS NULL OR pd.lado_a = v_ponta_b OR pd.lado_b = v_ponta_b) AS pode_jogar_ponta_b
    FROM mao m
    JOIN peca_domino pd ON m.id_peca = pd.id_peca
    WHERE m.id_jogador = p_jogador
      AND m.id_partida = p_partida
      AND (
          -- Se pontas são NULL (primeira jogada), qualquer peça pode jogar
          v_ponta_a IS NULL
          OR v_ponta_b IS NULL
          -- Ou a peça combina com alguma ponta
          OR pd.lado_a = v_ponta_a
          OR pd.lado_b = v_ponta_a
          OR pd.lado_a = v_ponta_b
          OR pd.lado_b = v_ponta_b
      );
END;
$$;
```

---

## 3. TRIGGERS (Gatilhos)

### 3.1 Verificar Fim de Partida (Trigger)

**Problema que resolve:** Detecta automaticamente quando uma partida termina (por vitória ou por jogo trancado) e calcula os pontos dos jogadores.

**Acionamento:** Executado APÓS cada DELETE na tabela `mao` (quando um jogador joga uma peça).

**Lógica implementada:**

1. **Detecção de vitória:** Verifica se o jogador que jogou ficou sem peças

   - Se sim, calcula os pontos dos adversários (soma dos valores das peças restantes)
   - Emite NOTICE informando o vencedor e os pontos de cada jogador

2. **Detecção de jogo trancado:** Chama a função `detectar_jogo_trancado()`
   - Se lançar exceção (jogo trancado), calcula os pontos de TODOS os jogadores
   - Emite NOTICE informando que o jogo está trancado e os pontos de cada jogador

**Benefícios:**

- Automatiza completamente a detecção de fim de jogo
- Elimina a necessidade de verificações manuais no código da aplicação
- Garante que os pontos sejam calculados imediatamente após cada jogada
- Permite auditoria através dos NOTICEs gerados

```sql
CREATE FUNCTION public.verificar_fim_partida() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id_partida INT;
    v_id_jogador INT;
    v_id_jogo INT;
    v_jogador_tem_pecas BOOLEAN;
    v_jogo_trancado BOOLEAN;
    v_total_pontos_jogador INT;
    v_jogador_rec RECORD;
BEGIN
    -- Obtém os dados da linha deletada
    v_id_partida := OLD.id_partida;
    v_id_jogador := OLD.id_jogador;

    -- Obtém o id do jogo
    SELECT id_jogo INTO v_id_jogo
    FROM partida
    WHERE id_partida = v_id_partida;

    -- Verifica se o jogador ainda tem peças na mão
    SELECT EXISTS (
        SELECT 1
        FROM mao
        WHERE id_jogador = v_id_jogador
          AND id_partida = v_id_partida
    ) INTO v_jogador_tem_pecas;

    -- Se o jogador não tem mais peças, ele ganhou
    IF NOT v_jogador_tem_pecas THEN
        RAISE NOTICE 'Jogador % ganhou a partida %!', v_id_jogador, v_id_partida;

        -- Calcula pontos dos outros jogadores
        FOR v_jogador_rec IN
            SELECT DISTINCT m.id_jogador
            FROM mao m
            WHERE m.id_partida = v_id_partida
              AND m.id_jogador != v_id_jogador
        LOOP
            SELECT COALESCE(SUM(pd.lado_a + pd.lado_b), 0) INTO v_total_pontos_jogador
            FROM mao m
            JOIN peca_domino pd ON m.id_peca = pd.id_peca
            WHERE m.id_jogador = v_jogador_rec.id_jogador
              AND m.id_partida = v_id_partida;

            RAISE NOTICE 'Jogador % ficou com % pontos na partida %',
                         v_jogador_rec.id_jogador, v_total_pontos_jogador, v_id_partida;
        END LOOP;

        RETURN OLD;
    END IF;

    -- Verifica se o jogo está trancado
    BEGIN
        v_jogo_trancado := detectar_jogo_trancado(v_id_partida);
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'JOGO TRANCADO detectado na partida %', v_id_partida;

            -- Calcula pontos de TODOS os jogadores
            FOR v_jogador_rec IN
                SELECT DISTINCT m.id_jogador
                FROM mao m
                WHERE m.id_partida = v_id_partida
            LOOP
                SELECT COALESCE(SUM(pd.lado_a + pd.lado_b), 0) INTO v_total_pontos_jogador
                FROM mao m
                JOIN peca_domino pd ON m.id_peca = pd.id_peca
                WHERE m.id_jogador = v_jogador_rec.id_jogador
                  AND m.id_partida = v_id_partida;

                RAISE NOTICE 'Jogador % ficou com % pontos (jogo trancado) na partida %',
                             v_jogador_rec.id_jogador, v_total_pontos_jogador, v_id_partida;
            END LOOP;
    END;

    RETURN OLD;
END;
$$;
```

---

## 4. VIEWS (Visões)

### 4.1 Lista de Partidas com Vencedores (View)

**Problema que resolve:** Fornece uma visão consolidada de todas as partidas e seus respectivos vencedores, facilitando consultas e relatórios.

**Lógica implementada:**

- Combina dados das tabelas `partida` e `dupla`
- Exibe informações completas da partida incluindo o nome da dupla vencedora
- Ordena por ID da partida para facilitar visualização cronológica

**Utilização:** Usada na interface para listar o histórico de partidas com seus vencedores.

```sql
CREATE VIEW public.vw_lista_partidas_vencedores AS
 SELECT p.id_partida,
    p.id_jogo,
    p.numero,
    p.vencedor_dupla,
    p.ponta_a,
    p.ponta_b,
    p.vez_do_jogador,
    d.nome_dupla
   FROM (public.partida p
     JOIN public.dupla d ON ((p.vencedor_dupla = d.id_dupla)))
  ORDER BY p.id_partida;
```

---

### 4.2 Ranking de Jogadores (View)

**Problema que resolve:** Cria um ranking automático dos jogadores baseado em suas vitórias, calculando tanto partidas ganhas quanto jogos completos vencidos.

**Lógica implementada:**

- Usa RIGHT JOINs para garantir que todos os jogadores apareçam no ranking, mesmo sem vitórias
- Conta o número de partidas ganhas por cada jogador
- Calcula automaticamente o número de jogos ganhos (dividindo por 50 partidas por jogo)
- Ordena por número de partidas ganhas (do maior para o menor)

**Utilização:** Usada na interface para exibir o ranking geral dos jogadores.

```sql
CREATE VIEW public.vw_ranking_jogadores AS
 SELECT j.nome AS nome_jogador,
    count(p.id_partida) AS partidas_ganhas,
    (count(p.id_partida) / 50) AS jogos_ganhos
   FROM (((public.partida p
     RIGHT JOIN public.dupla d ON ((p.vencedor_dupla = d.id_dupla)))
     RIGHT JOIN public.jogador_dupla jd ON ((d.id_dupla = jd.id_dupla)))
     RIGHT JOIN public.jogador j ON ((jd.id_jogador = j.id_jogador)))
  GROUP BY j.nome
  ORDER BY (count(p.id_partida)) DESC;
```
