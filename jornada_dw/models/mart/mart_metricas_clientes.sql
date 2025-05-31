{{
    config(
        materialized = 'table',
        unique_key = 'sk_cliente',
        tags = ['mart', 'metrics']
    )
}}

with 
dim_clientes as (
    select * from {{ ref('int_dim_clientes') }}
),

fact_pedidos as (
    select 
        *,
        cast(dt_pedido as date) as data_pedido
    from {{ ref('int_fact_pedidos') }}
),

dim_date as (
    select * from {{ ref('int_dim_date') }}
),

pedidos_por_cliente as (
    select
        dc.sk_cliente,
        dc.cpf,
        dc.nome,
        dc.estado,
        dc.cidade,
        
        -- Métricas de contagem
        count(distinct fp.sk_pedido) as total_pedidos,
        
        -- Métricas financeiras
        sum(fp.valor_total_pedido) as valor_total_gasto,
        avg(fp.valor_total_pedido) as ticket_medio,
        
        -- Datas importantes
        min(fp.dt_pedido) as data_primeiro_pedido,
        max(fp.dt_pedido) as data_ultimo_pedido,
        
        -- Análise temporal
        min(dd.year_number) as primeiro_ano_compra,
        max(dd.year_number) as ultimo_ano_compra,
        count(distinct dd.year_number) as total_anos_ativos,
        
        -- Estacionalidade
        count(distinct case when dd.month_name in ('December', 'January', 'February') then fp.sk_pedido end) as pedidos_verao,
        count(distinct case when dd.month_name in ('March', 'April', 'May') then fp.sk_pedido end) as pedidos_outono,
        count(distinct case when dd.month_name in ('June', 'July', 'August') then fp.sk_pedido end) as pedidos_inverno,
        count(distinct case when dd.month_name in ('September', 'October', 'November') then fp.sk_pedido end) as pedidos_primavera,
        
        -- Dias da semana com mais compras
        count(distinct case when dd.day_of_week_name = 'Sunday' then fp.sk_pedido end) as pedidos_domingo,
        count(distinct case when dd.day_of_week_name = 'Monday' then fp.sk_pedido end) as pedidos_segunda,
        count(distinct case when dd.day_of_week_name = 'Tuesday' then fp.sk_pedido end) as pedidos_terca,
        count(distinct case when dd.day_of_week_name = 'Wednesday' then fp.sk_pedido end) as pedidos_quarta,
        count(distinct case when dd.day_of_week_name = 'Thursday' then fp.sk_pedido end) as pedidos_quinta,
        count(distinct case when dd.day_of_week_name = 'Friday' then fp.sk_pedido end) as pedidos_sexta,
        count(distinct case when dd.day_of_week_name = 'Saturday' then fp.sk_pedido end) as pedidos_sabado,
        
        -- Frequência e recência
        (current_date - max(fp.dt_pedido)::date) as dias_desde_ultimo_pedido,
        
        -- Cálculo da frequência média de compras (em dias)
        case 
            when count(fp.sk_pedido) > 1 
            then (max(fp.dt_pedido)::date - min(fp.dt_pedido)::date)::float / 
                 nullif(count(fp.sk_pedido) - 1, 0)
            else null 
        end as frequencia_media_dias,
        
        -- Valor médio por mês
        case
            when count(distinct to_char(fp.dt_pedido, 'YYYY-MM')) > 0 
            then sum(fp.valor_total_pedido) / count(distinct to_char(fp.dt_pedido, 'YYYY-MM'))
            else 0 
        end as valor_medio_por_mes,
        
        -- Frequência de compras por mês
        case
            when count(distinct to_char(fp.dt_pedido, 'YYYY-MM')) > 0 
            then count(fp.sk_pedido)::float / count(distinct to_char(fp.dt_pedido, 'YYYY-MM'))
            else 0 
        end as frequencia_media_mensal
        
    from dim_clientes dc
    left join fact_pedidos fp 
        on dc.sk_cliente = fp.fk_cliente
    left join dim_date dd 
        on date_trunc('day', fp.dt_pedido) = dd.date_day
    group by 1, 2, 3, 4, 5
)

select 
    *,
    -- Análise RFM completa
    case
        when valor_total_gasto is null or valor_total_gasto = 0 then 'Inativo'
        when valor_total_gasto > 5000 and dias_desde_ultimo_pedido <= 30 and frequencia_media_mensal >= 2 then 'Campeão'
        when valor_total_gasto > 3000 and dias_desde_ultimo_pedido <= 60 then 'Cliente Fiel'
        when valor_total_gasto > 1000 and dias_desde_ultimo_pedido <= 90 then 'Potencial'
        when valor_total_gasto > 0 and dias_desde_ultimo_pedido > 180 then 'Em Risco de Churn'
        when valor_total_gasto > 0 then 'Em Observação'
        else 'Inativo'
    end as segmento_rfm,
    
    -- Score RFM (1-5, sendo 5 o melhor)
    case 
        when valor_total_gasto is null or valor_total_gasto = 0 then 1
        when valor_total_gasto > 5000 then 5
        when valor_total_gasto > 3000 then 4
        when valor_total_gasto > 1000 then 3
        when valor_total_gasto > 0 then 2
        else 1
    end as score_valor,
    
    case 
        when dias_desde_ultimo_pedido is null then 1
        when dias_desde_ultimo_pedido <= 30 then 5
        when dias_desde_ultimo_pedido <= 60 then 4
        when dias_desde_ultimo_pedido <= 90 then 3
        when dias_desde_ultimo_pedido <= 180 then 2
        else 1
    end as score_recencia,
    
    case 
        when frequencia_media_mensal is null or frequencia_media_mensal = 0 then 1
        when frequencia_media_mensal >= 4 then 5
        when frequencia_media_mensal >= 2 then 4
        when frequencia_media_mensal >= 1 then 3
        when frequencia_media_mensal > 0 then 2
        else 1
    end as score_frequencia,
    
    -- Estação preferida
    case
        when pedidos_verao > pedidos_outono and pedidos_verao > pedidos_inverno and pedidos_verao > pedidos_primavera then 'Verão'
        when pedidos_outono > pedidos_verao and pedidos_outono > pedidos_inverno and pedidos_outono > pedidos_primavera then 'Outono'
        when pedidos_inverno > pedidos_verao and pedidos_inverno > pedidos_outono and pedidos_inverno > pedidos_primavera then 'Inverno'
        when pedidos_primavera > pedidos_verao and pedidos_primavera > pedidos_outono and pedidos_primavera > pedidos_inverno then 'Primavera'
        else 'Sem preferência'
    end as estacao_preferida,
    
    -- Análise de crescimento
    case
        when total_anos_ativos > 1 and total_pedidos > 0 then
            case 
                when (select avg(total_pedidos::float / total_anos_ativos) 
                      from pedidos_por_cliente 
                      where total_anos_ativos > 1) > 0
                then (total_pedidos::float / total_anos_ativos) / 
                     (select avg(total_pedidos::float / total_anos_ativos) 
                      from pedidos_por_cliente 
                      where total_anos_ativos > 1)
                else 0
            end
        else 0
    end as taxa_crescimento_vs_media,
    
    -- Metadados
    current_timestamp as dbt_updated_at,
    '{{ run_started_at }}' as dbt_loaded_at
from pedidos_por_cliente
order by 
    case when valor_total_gasto is null then 1 else 0 end,  -- Inativos por último
    valor_total_gasto desc  -- Maiores valores primeiro