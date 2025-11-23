--
-- PostgreSQL database dump
--

-- Dumped from database version 18.1 (Debian 18.1-1.pgdg13+2)
-- Dumped by pg_dump version 18.1 (Debian 18.1-1.pgdg13+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: comprar_peca(integer, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

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


ALTER PROCEDURE public.comprar_peca(IN p_jogador integer, IN p_partida integer) OWNER TO postgres;

--
-- Name: detectar_jogo_trancado(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

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


ALTER FUNCTION public.detectar_jogo_trancado(p_partida integer) OWNER TO postgres;

--
-- Name: f_lista_jogadores_por_id_dupla(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.f_lista_jogadores_por_id_dupla(id_busca integer) RETURNS TABLE(nome character varying, email character varying, nome_dupla character varying)
    LANGUAGE sql
    AS $$
SELECT j.nome, j.email, d.nome_dupla FROM public.jogador j
INNER JOIN public.jogador_dupla jd ON j.id_jogador = jd.id_jogador
INNER JOIN public.dupla d ON jd.id_dupla = d.id_dupla
WHERE d.id_dupla = id_busca;
$$;


ALTER FUNCTION public.f_lista_jogadores_por_id_dupla(id_busca integer) OWNER TO postgres;

--
-- Name: jogadas_possiveis(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.jogadas_possiveis(p_jogador integer, p_partida integer) RETURNS TABLE(id_peca integer)
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
        pd.id_peca
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


ALTER FUNCTION public.jogadas_possiveis(p_jogador integer, p_partida integer) OWNER TO postgres;

--
-- Name: jogar_peca(integer, integer, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.jogar_peca(IN p_jogador integer, IN p_partida integer, IN p_peca integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    p_mao INT;
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

    -- 2. VERIFICA SE O JOGADOR TEM A PECA NA MAO
    SELECT id_mao INTO p_mao
    FROM mao
    WHERE id_jogador = p_jogador
      AND id_partida = p_partida
      AND id_peca = p_peca;

    IF p_mao IS NULL THEN
        RAISE EXCEPTION 'Jogador não possui essa peça';
    END IF;

    -- 3. INSERE NA MESA
    INSERT INTO mesa (id_partida, id_peca, posicao)
    VALUES (
        p_partida,
        p_peca,
        (SELECT COALESCE(MAX(posicao), 0) + 1 FROM mesa WHERE id_partida = p_partida)
    );

    -- 4. REMOVE DA MAO
    DELETE FROM mao WHERE id_mao = p_mao;
END;
$$;


ALTER PROCEDURE public.jogar_peca(IN p_jogador integer, IN p_partida integer, IN p_peca integer) OWNER TO postgres;

--
-- Name: jogar_peca(integer, integer, integer, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

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


ALTER PROCEDURE public.jogar_peca(IN p_jogador integer, IN p_partida integer, IN p_peca integer, IN p_lado_mesa integer) OWNER TO postgres;

--
-- Name: retorna_soma_lados_por_id_peca(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.retorna_soma_lados_por_id_peca(id_busca integer) RETURNS integer
    LANGUAGE sql
    AS $$
SELECT pd.lado_a + pd.lado_b as soma_lados FROM public.peca_domino pd
WHERE pd.id_peca = id_busca
$$;


ALTER FUNCTION public.retorna_soma_lados_por_id_peca(id_busca integer) OWNER TO postgres;

--
-- Name: verificar_fim_partida(); Type: FUNCTION; Schema: public; Owner: postgres
--

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
        -- Atualiza o vencedor da partida (assumindo que existe campo vencedor_jogador)
        -- Se não existir, você pode adicionar esse campo ou usar outra lógica
        RAISE NOTICE 'Jogador % ganhou a partida %!', v_id_jogador, v_id_partida;
        
        -- Calcula pontos dos outros jogadores e soma na tabela jogador_jogo
        FOR v_jogador_rec IN 
            SELECT DISTINCT m.id_jogador
            FROM mao m
            WHERE m.id_partida = v_id_partida
              AND m.id_jogador != v_id_jogador
        LOOP
            -- Calcula soma dos pontos das peças restantes do jogador
            SELECT COALESCE(SUM(pd.lado_a + pd.lado_b), 0) INTO v_total_pontos_jogador
            FROM mao m
            JOIN peca_domino pd ON m.id_peca = pd.id_peca
            WHERE m.id_jogador = v_jogador_rec.id_jogador
              AND m.id_partida = v_id_partida;
            
            -- Atualiza ou insere na tabela de pontos (ajuste conforme sua estrutura)
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
            -- Jogo está trancado
            RAISE NOTICE 'JOGO TRANCADO detectado na partida %', v_id_partida;
            
            -- Calcula pontos de TODOS os jogadores
            FOR v_jogador_rec IN 
                SELECT DISTINCT m.id_jogador
                FROM mao m
                WHERE m.id_partida = v_id_partida
            LOOP
                -- Calcula soma dos pontos das peças restantes do jogador
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


ALTER FUNCTION public.verificar_fim_partida() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: dupla; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.dupla (
    id_dupla integer NOT NULL,
    nome_dupla character varying(60) NOT NULL
);


ALTER TABLE public.dupla OWNER TO postgres;

--
-- Name: dupla_id_dupla_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.dupla_id_dupla_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.dupla_id_dupla_seq OWNER TO postgres;

--
-- Name: dupla_id_dupla_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.dupla_id_dupla_seq OWNED BY public.dupla.id_dupla;


--
-- Name: jogada; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.jogada (
    id_jogada integer NOT NULL,
    id_partida integer,
    id_jogador integer,
    id_peca integer,
    tipo character varying(20),
    feito_em timestamp without time zone DEFAULT now()
);


ALTER TABLE public.jogada OWNER TO postgres;

--
-- Name: jogada_id_jogada_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.jogada_id_jogada_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.jogada_id_jogada_seq OWNER TO postgres;

--
-- Name: jogada_id_jogada_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.jogada_id_jogada_seq OWNED BY public.jogada.id_jogada;


--
-- Name: jogador; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.jogador (
    id_jogador integer NOT NULL,
    nome character varying(60) NOT NULL,
    email character varying(100) NOT NULL
);


ALTER TABLE public.jogador OWNER TO postgres;

--
-- Name: jogador_dupla; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.jogador_dupla (
    id_dupla integer NOT NULL,
    id_jogador integer NOT NULL
);


ALTER TABLE public.jogador_dupla OWNER TO postgres;

--
-- Name: jogador_id_jogador_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.jogador_id_jogador_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.jogador_id_jogador_seq OWNER TO postgres;

--
-- Name: jogador_id_jogador_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.jogador_id_jogador_seq OWNED BY public.jogador.id_jogador;


--
-- Name: jogador_jogo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.jogador_jogo (
    id_jogo integer NOT NULL,
    id_jogador integer NOT NULL,
    posicao integer NOT NULL
);


ALTER TABLE public.jogador_jogo OWNER TO postgres;

--
-- Name: jogo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.jogo (
    id_jogo integer NOT NULL,
    nome_jogo character varying(80),
    tipo_jogo integer NOT NULL,
    criado_em timestamp without time zone DEFAULT now(),
    CONSTRAINT jogo_tipo_jogo_check CHECK ((tipo_jogo = ANY (ARRAY[2, 3, 4])))
);


ALTER TABLE public.jogo OWNER TO postgres;

--
-- Name: jogo_id_jogo_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.jogo_id_jogo_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.jogo_id_jogo_seq OWNER TO postgres;

--
-- Name: jogo_id_jogo_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.jogo_id_jogo_seq OWNED BY public.jogo.id_jogo;


--
-- Name: mao; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.mao (
    id_mao integer NOT NULL,
    id_partida integer,
    id_jogador integer,
    id_peca integer
);


ALTER TABLE public.mao OWNER TO postgres;

--
-- Name: mao_id_mao_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.mao_id_mao_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.mao_id_mao_seq OWNER TO postgres;

--
-- Name: mao_id_mao_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.mao_id_mao_seq OWNED BY public.mao.id_mao;


--
-- Name: mesa; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.mesa (
    id_mesa integer NOT NULL,
    id_partida integer,
    id_peca integer,
    posicao integer
);


ALTER TABLE public.mesa OWNER TO postgres;

--
-- Name: mesa_id_mesa_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.mesa_id_mesa_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.mesa_id_mesa_seq OWNER TO postgres;

--
-- Name: mesa_id_mesa_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.mesa_id_mesa_seq OWNED BY public.mesa.id_mesa;


--
-- Name: monte; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.monte (
    id_monte integer NOT NULL,
    id_partida integer,
    id_peca integer,
    ordem integer
);


ALTER TABLE public.monte OWNER TO postgres;

--
-- Name: monte_id_monte_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.monte_id_monte_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.monte_id_monte_seq OWNER TO postgres;

--
-- Name: monte_id_monte_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.monte_id_monte_seq OWNED BY public.monte.id_monte;


--
-- Name: partida; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.partida (
    id_partida integer NOT NULL,
    id_jogo integer,
    numero integer NOT NULL,
    vencedor_dupla integer,
    ponta_a integer,
    ponta_b integer,
    vez_do_jogador integer
);


ALTER TABLE public.partida OWNER TO postgres;

--
-- Name: partida_id_partida_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.partida_id_partida_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.partida_id_partida_seq OWNER TO postgres;

--
-- Name: partida_id_partida_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.partida_id_partida_seq OWNED BY public.partida.id_partida;


--
-- Name: peca_domino; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.peca_domino (
    id_peca integer NOT NULL,
    lado_a integer NOT NULL,
    lado_b integer NOT NULL
);


ALTER TABLE public.peca_domino OWNER TO postgres;

--
-- Name: peca_domino_id_peca_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.peca_domino_id_peca_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.peca_domino_id_peca_seq OWNER TO postgres;

--
-- Name: peca_domino_id_peca_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.peca_domino_id_peca_seq OWNED BY public.peca_domino.id_peca;


--
-- Name: peca_jogada; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.peca_jogada (
    id_peca_jogada integer NOT NULL,
    id_partida integer NOT NULL,
    id_peca integer NOT NULL,
    id_jogador integer NOT NULL,
    lado_jogada integer NOT NULL,
    ordem_jogada integer NOT NULL,
    lado_mesa integer,
    CONSTRAINT peca_jogada_lado_jogada_check CHECK ((lado_jogada = ANY (ARRAY[1, 2])))
);


ALTER TABLE public.peca_jogada OWNER TO postgres;

--
-- Name: peca_jogada_id_peca_jogada_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.peca_jogada_id_peca_jogada_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.peca_jogada_id_peca_jogada_seq OWNER TO postgres;

--
-- Name: peca_jogada_id_peca_jogada_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.peca_jogada_id_peca_jogada_seq OWNED BY public.peca_jogada.id_peca_jogada;


--
-- Name: vw_lista_partidas_vencedores; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER VIEW public.vw_lista_partidas_vencedores OWNER TO postgres;

--
-- Name: vw_ranking_jogadores; Type: VIEW; Schema: public; Owner: postgres
--

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


ALTER VIEW public.vw_ranking_jogadores OWNER TO postgres;

--
-- Name: dupla id_dupla; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dupla ALTER COLUMN id_dupla SET DEFAULT nextval('public.dupla_id_dupla_seq'::regclass);


--
-- Name: jogada id_jogada; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jogada ALTER COLUMN id_jogada SET DEFAULT nextval('public.jogada_id_jogada_seq'::regclass);


--
-- Name: jogador id_jogador; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jogador ALTER COLUMN id_jogador SET DEFAULT nextval('public.jogador_id_jogador_seq'::regclass);


--
-- Name: jogo id_jogo; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jogo ALTER COLUMN id_jogo SET DEFAULT nextval('public.jogo_id_jogo_seq'::regclass);


--
-- Name: mao id_mao; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mao ALTER COLUMN id_mao SET DEFAULT nextval('public.mao_id_mao_seq'::regclass);


--
-- Name: mesa id_mesa; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mesa ALTER COLUMN id_mesa SET DEFAULT nextval('public.mesa_id_mesa_seq'::regclass);


--
-- Name: monte id_monte; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.monte ALTER COLUMN id_monte SET DEFAULT nextval('public.monte_id_monte_seq'::regclass);


--
-- Name: partida id_partida; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partida ALTER COLUMN id_partida SET DEFAULT nextval('public.partida_id_partida_seq'::regclass);


--
-- Name: peca_domino id_peca; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.peca_domino ALTER COLUMN id_peca SET DEFAULT nextval('public.peca_domino_id_peca_seq'::regclass);


--
-- Name: peca_jogada id_peca_jogada; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.peca_jogada ALTER COLUMN id_peca_jogada SET DEFAULT nextval('public.peca_jogada_id_peca_jogada_seq'::regclass);


--
-- Data for Name: dupla; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.dupla (id_dupla, nome_dupla) VALUES (1, 'dupla da pesada');
INSERT INTO public.dupla (id_dupla, nome_dupla) VALUES (2, 'outra dupla bacanau');
INSERT INTO public.dupla (id_dupla, nome_dupla) VALUES (3, 'MAIS UMA DUPLA');
INSERT INTO public.dupla (id_dupla, nome_dupla) VALUES (4, 'DUPLA SEM NADA');


--
-- Data for Name: jogada; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.jogada (id_jogada, id_partida, id_jogador, id_peca, tipo, feito_em) VALUES (1, 7, 3, 23, 'Jogada', '2025-11-22 04:31:29.302646');
INSERT INTO public.jogada (id_jogada, id_partida, id_jogador, id_peca, tipo, feito_em) VALUES (2, 8, 3, 20, 'Jogada', '2025-11-22 04:47:59.656814');
INSERT INTO public.jogada (id_jogada, id_partida, id_jogador, id_peca, tipo, feito_em) VALUES (3, 4, 2, 4, 'Jogada', '2025-11-23 05:35:07.004948');
INSERT INTO public.jogada (id_jogada, id_partida, id_jogador, id_peca, tipo, feito_em) VALUES (4, 4, 2, 27, 'Jogada', '2025-11-23 07:15:51.859712');
INSERT INTO public.jogada (id_jogada, id_partida, id_jogador, id_peca, tipo, feito_em) VALUES (5, 4, 2, 12, 'Jogada', '2025-11-23 07:17:00.896092');
INSERT INTO public.jogada (id_jogada, id_partida, id_jogador, id_peca, tipo, feito_em) VALUES (6, 4, 2, 12, 'Jogada', '2025-11-23 07:21:38.800612');
INSERT INTO public.jogada (id_jogada, id_partida, id_jogador, id_peca, tipo, feito_em) VALUES (7, 4, 2, 12, 'Jogada', '2025-11-23 07:22:15.00054');
INSERT INTO public.jogada (id_jogada, id_partida, id_jogador, id_peca, tipo, feito_em) VALUES (8, 4, 2, 12, 'Jogada', '2025-11-23 07:25:04.524659');


--
-- Data for Name: jogador; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.jogador (id_jogador, nome, email) VALUES (1, 'Alice', 'alice@exemplo.com');
INSERT INTO public.jogador (id_jogador, nome, email) VALUES (2, 'Bob', 'bob@exemplo.com');
INSERT INTO public.jogador (id_jogador, nome, email) VALUES (3, 'Player 1 (Voce)', 'player1@test.com');
INSERT INTO public.jogador (id_jogador, nome, email) VALUES (4, 'Player 2 (Sua dupla)', 'player2@test.com');
INSERT INTO public.jogador (id_jogador, nome, email) VALUES (5, 'rafaela', 'rafaela@exemplo.com');


--
-- Data for Name: jogador_dupla; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.jogador_dupla (id_dupla, id_jogador) VALUES (1, 1);
INSERT INTO public.jogador_dupla (id_dupla, id_jogador) VALUES (1, 2);
INSERT INTO public.jogador_dupla (id_dupla, id_jogador) VALUES (2, 3);
INSERT INTO public.jogador_dupla (id_dupla, id_jogador) VALUES (2, 4);
INSERT INTO public.jogador_dupla (id_dupla, id_jogador) VALUES (3, 1);
INSERT INTO public.jogador_dupla (id_dupla, id_jogador) VALUES (3, 4);
INSERT INTO public.jogador_dupla (id_dupla, id_jogador) VALUES (4, 2);
INSERT INTO public.jogador_dupla (id_dupla, id_jogador) VALUES (4, 5);


--
-- Data for Name: jogador_jogo; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.jogador_jogo (id_jogo, id_jogador, posicao) VALUES (4, 2, 0);
INSERT INTO public.jogador_jogo (id_jogo, id_jogador, posicao) VALUES (4, 1, 0);
INSERT INTO public.jogador_jogo (id_jogo, id_jogador, posicao) VALUES (5, 2, 0);
INSERT INTO public.jogador_jogo (id_jogo, id_jogador, posicao) VALUES (6, 1, 0);
INSERT INTO public.jogador_jogo (id_jogo, id_jogador, posicao) VALUES (6, 2, 0);
INSERT INTO public.jogador_jogo (id_jogo, id_jogador, posicao) VALUES (7, 1, 0);
INSERT INTO public.jogador_jogo (id_jogo, id_jogador, posicao) VALUES (7, 2, 0);
INSERT INTO public.jogador_jogo (id_jogo, id_jogador, posicao) VALUES (8, 1, 0);
INSERT INTO public.jogador_jogo (id_jogo, id_jogador, posicao) VALUES (8, 2, 0);
INSERT INTO public.jogador_jogo (id_jogo, id_jogador, posicao) VALUES (9, 1, 0);
INSERT INTO public.jogador_jogo (id_jogo, id_jogador, posicao) VALUES (9, 2, 0);
INSERT INTO public.jogador_jogo (id_jogo, id_jogador, posicao) VALUES (10, 3, 1);
INSERT INTO public.jogador_jogo (id_jogo, id_jogador, posicao) VALUES (10, 4, 2);
INSERT INTO public.jogador_jogo (id_jogo, id_jogador, posicao) VALUES (11, 3, 1);
INSERT INTO public.jogador_jogo (id_jogo, id_jogador, posicao) VALUES (11, 4, 2);
INSERT INTO public.jogador_jogo (id_jogo, id_jogador, posicao) VALUES (12, 3, 1);
INSERT INTO public.jogador_jogo (id_jogo, id_jogador, posicao) VALUES (12, 4, 2);
INSERT INTO public.jogador_jogo (id_jogo, id_jogador, posicao) VALUES (13, 3, 1);
INSERT INTO public.jogador_jogo (id_jogo, id_jogador, posicao) VALUES (13, 4, 2);


--
-- Data for Name: jogo; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.jogo (id_jogo, nome_jogo, tipo_jogo, criado_em) VALUES (1, NULL, 2, '2025-11-22 02:57:03.318237');
INSERT INTO public.jogo (id_jogo, nome_jogo, tipo_jogo, criado_em) VALUES (2, NULL, 2, '2025-11-22 02:58:10.265368');
INSERT INTO public.jogo (id_jogo, nome_jogo, tipo_jogo, criado_em) VALUES (3, NULL, 2, '2025-11-22 03:04:43.465218');
INSERT INTO public.jogo (id_jogo, nome_jogo, tipo_jogo, criado_em) VALUES (4, NULL, 2, '2025-11-22 03:06:23.375051');
INSERT INTO public.jogo (id_jogo, nome_jogo, tipo_jogo, criado_em) VALUES (5, NULL, 2, '2025-11-22 03:15:20.560566');
INSERT INTO public.jogo (id_jogo, nome_jogo, tipo_jogo, criado_em) VALUES (6, NULL, 2, '2025-11-22 03:16:38.282634');
INSERT INTO public.jogo (id_jogo, nome_jogo, tipo_jogo, criado_em) VALUES (7, NULL, 2, '2025-11-22 03:22:44.017236');
INSERT INTO public.jogo (id_jogo, nome_jogo, tipo_jogo, criado_em) VALUES (8, NULL, 2, '2025-11-22 03:28:53.375821');
INSERT INTO public.jogo (id_jogo, nome_jogo, tipo_jogo, criado_em) VALUES (9, NULL, 2, '2025-11-22 03:34:58.216976');
INSERT INTO public.jogo (id_jogo, nome_jogo, tipo_jogo, criado_em) VALUES (10, 'Domino Teste 2P', 2, '2025-11-22 04:04:52.895112');
INSERT INTO public.jogo (id_jogo, nome_jogo, tipo_jogo, criado_em) VALUES (11, 'Domino Teste 2P', 2, '2025-11-22 04:12:08.044961');
INSERT INTO public.jogo (id_jogo, nome_jogo, tipo_jogo, criado_em) VALUES (12, 'Domino Teste 2P', 2, '2025-11-22 04:16:28.956663');
INSERT INTO public.jogo (id_jogo, nome_jogo, tipo_jogo, criado_em) VALUES (13, 'Domino Teste 2P', 2, '2025-11-22 04:44:50.028491');


--
-- Data for Name: mao; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (2, 4, 1, 23);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (3, 4, 1, 20);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (4, 4, 1, 26);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (6, 4, 1, 15);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (15, 5, 3, 6);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (16, 5, 3, 20);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (17, 5, 3, 2);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (18, 5, 3, 15);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (19, 5, 3, 17);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (20, 5, 3, 19);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (21, 5, 3, 1);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (22, 5, 4, 13);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (23, 5, 4, 3);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (24, 5, 4, 11);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (25, 5, 4, 12);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (26, 5, 4, 22);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (27, 5, 4, 28);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (28, 5, 4, 16);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (29, 6, 3, 24);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (30, 6, 3, 25);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (31, 6, 3, 14);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (32, 6, 3, 2);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (33, 6, 3, 28);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (34, 6, 3, 10);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (35, 6, 3, 5);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (36, 6, 4, 22);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (37, 6, 4, 20);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (38, 6, 4, 7);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (39, 6, 4, 8);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (40, 6, 4, 11);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (41, 6, 4, 6);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (42, 6, 4, 19);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (43, 7, 3, 22);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (44, 7, 3, 9);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (45, 7, 3, 10);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (46, 7, 3, 5);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (48, 7, 3, 27);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (49, 7, 3, 2);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (50, 7, 4, 12);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (51, 7, 4, 18);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (52, 7, 4, 17);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (53, 7, 4, 16);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (54, 7, 4, 26);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (55, 7, 4, 7);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (56, 7, 4, 14);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (57, 8, 3, 4);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (59, 8, 3, 8);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (60, 8, 3, 7);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (61, 8, 3, 18);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (62, 8, 3, 12);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (63, 8, 3, 13);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (64, 8, 4, 6);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (65, 8, 4, 17);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (66, 8, 4, 5);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (67, 8, 4, 24);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (68, 8, 4, 10);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (69, 8, 4, 22);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (70, 8, 4, 1);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (71, 3, 1, 27);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (96, 4, 1, 10);
INSERT INTO public.mao (id_mao, id_partida, id_jogador, id_peca) VALUES (98, 4, 1, 27);


--
-- Data for Name: mesa; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.mesa (id_mesa, id_partida, id_peca, posicao) VALUES (2, 4, 3, 1);
INSERT INTO public.mesa (id_mesa, id_partida, id_peca, posicao) VALUES (3, 4, 12, 2);


--
-- Data for Name: monte; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (2, 3, 13, 0);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (3, 3, 8, 0);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (4, 3, 26, 0);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (5, 3, 10, 0);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (6, 3, 9, 0);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (7, 3, 12, 0);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (8, 3, 16, 0);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (9, 3, 11, 0);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (10, 3, 2, 0);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (11, 3, 21, 0);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (12, 3, 15, 0);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (13, 3, 17, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (14, 3, 25, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (15, 3, 22, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (16, 3, 18, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (17, 3, 20, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (18, 3, 1, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (19, 3, 5, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (20, 3, 3, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (21, 3, 19, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (22, 3, 23, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (23, 3, 14, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (24, 3, 4, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (25, 3, 7, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (26, 3, 24, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (27, 3, 6, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (28, 3, 28, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (71, 5, 5, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (72, 5, 4, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (73, 5, 26, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (74, 5, 10, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (75, 5, 18, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (76, 5, 8, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (77, 5, 23, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (78, 5, 27, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (79, 5, 21, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (80, 5, 7, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (81, 5, 9, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (82, 5, 14, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (83, 5, 24, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (84, 5, 25, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (99, 6, 23, 0);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (100, 6, 17, 0);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (101, 6, 12, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (102, 6, 9, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (103, 6, 3, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (104, 6, 13, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (105, 6, 26, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (106, 6, 1, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (107, 6, 27, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (108, 6, 16, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (109, 6, 21, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (110, 6, 18, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (111, 6, 15, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (112, 6, 4, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (127, 7, 1, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (128, 7, 21, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (129, 7, 3, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (130, 7, 19, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (131, 7, 25, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (132, 7, 6, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (133, 7, 24, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (134, 7, 20, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (135, 7, 11, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (136, 7, 4, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (137, 7, 13, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (138, 7, 8, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (139, 7, 28, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (140, 7, 15, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (155, 8, 2, 0);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (156, 8, 21, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (157, 8, 26, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (158, 8, 15, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (159, 8, 23, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (160, 8, 3, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (161, 8, 11, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (162, 8, 28, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (163, 8, 19, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (164, 8, 27, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (165, 8, 14, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (166, 8, 9, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (167, 8, 25, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (168, 8, 16, 1);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (187, 4, 10, 0);
INSERT INTO public.monte (id_monte, id_partida, id_peca, ordem) VALUES (188, 4, 10, 0);


--
-- Data for Name: partida; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (5, 10, 1, NULL, NULL, NULL, 3);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (6, 11, 1, NULL, NULL, NULL, 3);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (7, 12, 1, NULL, 4, 4, 4);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (8, 13, 1, NULL, 3, 4, 4);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (1, 6, 1, 1, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (2, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (3, 8, 1, 3, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (9, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (10, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (11, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (12, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (13, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (14, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (15, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (16, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (17, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (18, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (19, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (20, 7, 2, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (21, 7, 2, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (22, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (23, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (24, 7, 2, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (25, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (26, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (27, 7, 2, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (28, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (29, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (30, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (31, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (32, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (33, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (34, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (35, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (36, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (37, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (38, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (39, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (40, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (41, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (42, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (43, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (44, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (45, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (46, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (47, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (48, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (49, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (50, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (51, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (52, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (53, 7, 2, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (54, 7, 2, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (55, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (56, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (57, 7, 2, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (58, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (59, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (60, 7, 2, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (61, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (62, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (63, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (64, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (65, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (66, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (67, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (68, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (69, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (70, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (71, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (72, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (73, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (74, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (75, 7, 1, 2, NULL, NULL, NULL);
INSERT INTO public.partida (id_partida, id_jogo, numero, vencedor_dupla, ponta_a, ponta_b, vez_do_jogador) VALUES (4, 9, 1, NULL, 5, 5, 1);


--
-- Data for Name: peca_domino; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (1, 0, 0);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (2, 0, 1);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (3, 0, 2);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (4, 0, 3);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (5, 0, 4);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (6, 0, 5);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (7, 0, 6);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (8, 1, 1);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (9, 1, 2);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (10, 1, 3);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (11, 1, 4);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (12, 1, 5);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (13, 1, 6);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (14, 2, 2);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (15, 2, 3);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (16, 2, 4);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (17, 2, 5);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (18, 2, 6);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (19, 3, 3);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (20, 3, 4);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (21, 3, 5);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (22, 3, 6);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (23, 4, 4);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (24, 4, 5);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (25, 4, 6);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (26, 5, 5);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (27, 5, 6);
INSERT INTO public.peca_domino (id_peca, lado_a, lado_b) VALUES (28, 6, 6);


--
-- Data for Name: peca_jogada; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.peca_jogada (id_peca_jogada, id_partida, id_peca, id_jogador, lado_jogada, ordem_jogada, lado_mesa) VALUES (3, 7, 23, 3, 1, 1, NULL);
INSERT INTO public.peca_jogada (id_peca_jogada, id_partida, id_peca, id_jogador, lado_jogada, ordem_jogada, lado_mesa) VALUES (4, 8, 20, 3, 1, 1, NULL);
INSERT INTO public.peca_jogada (id_peca_jogada, id_partida, id_peca, id_jogador, lado_jogada, ordem_jogada, lado_mesa) VALUES (5, 4, 4, 2, 1, 1, NULL);
INSERT INTO public.peca_jogada (id_peca_jogada, id_partida, id_peca, id_jogador, lado_jogada, ordem_jogada, lado_mesa) VALUES (6, 4, 27, 2, 1, 2, NULL);
INSERT INTO public.peca_jogada (id_peca_jogada, id_partida, id_peca, id_jogador, lado_jogada, ordem_jogada, lado_mesa) VALUES (7, 4, 12, 2, 1, 3, NULL);
INSERT INTO public.peca_jogada (id_peca_jogada, id_partida, id_peca, id_jogador, lado_jogada, ordem_jogada, lado_mesa) VALUES (8, 4, 12, 2, 1, 4, NULL);
INSERT INTO public.peca_jogada (id_peca_jogada, id_partida, id_peca, id_jogador, lado_jogada, ordem_jogada, lado_mesa) VALUES (9, 4, 12, 2, 1, 5, NULL);
INSERT INTO public.peca_jogada (id_peca_jogada, id_partida, id_peca, id_jogador, lado_jogada, ordem_jogada, lado_mesa) VALUES (10, 4, 12, 2, 1, 6, NULL);


--
-- Name: dupla_id_dupla_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.dupla_id_dupla_seq', 4, true);


--
-- Name: jogada_id_jogada_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.jogada_id_jogada_seq', 8, true);


--
-- Name: jogador_id_jogador_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.jogador_id_jogador_seq', 5, true);


--
-- Name: jogo_id_jogo_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.jogo_id_jogo_seq', 13, true);


--
-- Name: mao_id_mao_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.mao_id_mao_seq', 104, true);


--
-- Name: mesa_id_mesa_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.mesa_id_mesa_seq', 3, true);


--
-- Name: monte_id_monte_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.monte_id_monte_seq', 188, true);


--
-- Name: partida_id_partida_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.partida_id_partida_seq', 75, true);


--
-- Name: peca_domino_id_peca_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.peca_domino_id_peca_seq', 28, true);


--
-- Name: peca_jogada_id_peca_jogada_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.peca_jogada_id_peca_jogada_seq', 10, true);


--
-- Name: dupla dupla_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dupla
    ADD CONSTRAINT dupla_pkey PRIMARY KEY (id_dupla);


--
-- Name: jogada jogada_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jogada
    ADD CONSTRAINT jogada_pkey PRIMARY KEY (id_jogada);


--
-- Name: jogador_dupla jogador_dupla_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jogador_dupla
    ADD CONSTRAINT jogador_dupla_pkey PRIMARY KEY (id_dupla, id_jogador);


--
-- Name: jogador jogador_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jogador
    ADD CONSTRAINT jogador_email_key UNIQUE (email);


--
-- Name: jogador_jogo jogador_jogo_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jogador_jogo
    ADD CONSTRAINT jogador_jogo_pkey PRIMARY KEY (id_jogo, id_jogador);


--
-- Name: jogador jogador_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jogador
    ADD CONSTRAINT jogador_pkey PRIMARY KEY (id_jogador);


--
-- Name: jogo jogo_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jogo
    ADD CONSTRAINT jogo_pkey PRIMARY KEY (id_jogo);


--
-- Name: mao mao_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mao
    ADD CONSTRAINT mao_pkey PRIMARY KEY (id_mao);


--
-- Name: mesa mesa_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mesa
    ADD CONSTRAINT mesa_pkey PRIMARY KEY (id_mesa);


--
-- Name: monte monte_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.monte
    ADD CONSTRAINT monte_pkey PRIMARY KEY (id_monte);


--
-- Name: partida partida_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partida
    ADD CONSTRAINT partida_pkey PRIMARY KEY (id_partida);


--
-- Name: peca_domino peca_domino_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.peca_domino
    ADD CONSTRAINT peca_domino_pkey PRIMARY KEY (id_peca);


--
-- Name: peca_jogada peca_jogada_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.peca_jogada
    ADD CONSTRAINT peca_jogada_pkey PRIMARY KEY (id_peca_jogada);


--
-- Name: idx_peca_jogada_partida; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_peca_jogada_partida ON public.peca_jogada USING btree (id_partida);


--
-- Name: mao trigger_verificar_fim_partida; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_verificar_fim_partida AFTER DELETE ON public.mao FOR EACH ROW EXECUTE FUNCTION public.verificar_fim_partida();


--
-- Name: jogada jogada_id_jogador_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jogada
    ADD CONSTRAINT jogada_id_jogador_fkey FOREIGN KEY (id_jogador) REFERENCES public.jogador(id_jogador);


--
-- Name: jogada jogada_id_partida_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jogada
    ADD CONSTRAINT jogada_id_partida_fkey FOREIGN KEY (id_partida) REFERENCES public.partida(id_partida);


--
-- Name: jogada jogada_id_peca_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jogada
    ADD CONSTRAINT jogada_id_peca_fkey FOREIGN KEY (id_peca) REFERENCES public.peca_domino(id_peca);


--
-- Name: jogador_dupla jogador_dupla_id_dupla_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jogador_dupla
    ADD CONSTRAINT jogador_dupla_id_dupla_fkey FOREIGN KEY (id_dupla) REFERENCES public.dupla(id_dupla);


--
-- Name: jogador_dupla jogador_dupla_id_jogador_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jogador_dupla
    ADD CONSTRAINT jogador_dupla_id_jogador_fkey FOREIGN KEY (id_jogador) REFERENCES public.jogador(id_jogador);


--
-- Name: jogador_jogo jogador_jogo_id_jogador_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jogador_jogo
    ADD CONSTRAINT jogador_jogo_id_jogador_fkey FOREIGN KEY (id_jogador) REFERENCES public.jogador(id_jogador);


--
-- Name: jogador_jogo jogador_jogo_id_jogo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.jogador_jogo
    ADD CONSTRAINT jogador_jogo_id_jogo_fkey FOREIGN KEY (id_jogo) REFERENCES public.jogo(id_jogo);


--
-- Name: mao mao_id_jogador_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mao
    ADD CONSTRAINT mao_id_jogador_fkey FOREIGN KEY (id_jogador) REFERENCES public.jogador(id_jogador);


--
-- Name: mao mao_id_partida_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mao
    ADD CONSTRAINT mao_id_partida_fkey FOREIGN KEY (id_partida) REFERENCES public.partida(id_partida);


--
-- Name: mao mao_id_peca_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mao
    ADD CONSTRAINT mao_id_peca_fkey FOREIGN KEY (id_peca) REFERENCES public.peca_domino(id_peca);


--
-- Name: mesa mesa_id_partida_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mesa
    ADD CONSTRAINT mesa_id_partida_fkey FOREIGN KEY (id_partida) REFERENCES public.partida(id_partida);


--
-- Name: mesa mesa_id_peca_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mesa
    ADD CONSTRAINT mesa_id_peca_fkey FOREIGN KEY (id_peca) REFERENCES public.peca_domino(id_peca);


--
-- Name: monte monte_id_partida_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.monte
    ADD CONSTRAINT monte_id_partida_fkey FOREIGN KEY (id_partida) REFERENCES public.partida(id_partida);


--
-- Name: monte monte_id_peca_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.monte
    ADD CONSTRAINT monte_id_peca_fkey FOREIGN KEY (id_peca) REFERENCES public.peca_domino(id_peca);


--
-- Name: partida partida_id_jogo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partida
    ADD CONSTRAINT partida_id_jogo_fkey FOREIGN KEY (id_jogo) REFERENCES public.jogo(id_jogo);


--
-- Name: partida partida_vencedor_dupla_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partida
    ADD CONSTRAINT partida_vencedor_dupla_fkey FOREIGN KEY (vencedor_dupla) REFERENCES public.dupla(id_dupla);


--
-- Name: partida partida_vez_do_jogador_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partida
    ADD CONSTRAINT partida_vez_do_jogador_fkey FOREIGN KEY (vez_do_jogador) REFERENCES public.jogador(id_jogador);


--
-- Name: peca_jogada peca_jogada_id_jogador_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.peca_jogada
    ADD CONSTRAINT peca_jogada_id_jogador_fkey FOREIGN KEY (id_jogador) REFERENCES public.jogador(id_jogador);


--
-- Name: peca_jogada peca_jogada_id_partida_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.peca_jogada
    ADD CONSTRAINT peca_jogada_id_partida_fkey FOREIGN KEY (id_partida) REFERENCES public.partida(id_partida);


--
-- Name: peca_jogada peca_jogada_id_peca_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.peca_jogada
    ADD CONSTRAINT peca_jogada_id_peca_fkey FOREIGN KEY (id_peca) REFERENCES public.peca_domino(id_peca);


--
-- PostgreSQL database dump complete
--


