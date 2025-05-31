{{
    config(
        materialized = 'table',
        unique_key = 'date_day',
        tags = ['mart', 'metrics']
    )
}}

with fact_pedidos as (
    select 
        *,
        cast(dt_pedido as date) as data_pedido
    from {{ ref('int_fact_pedidos') }}
),

dim_date as (
    select * from {{ ref('int_dim_date') }}
),

vendas_por_dia as (
    select
        d.date_day,
        
        -- Dimensões temporais
        d.day_of_week_name as dia_da_semana,
        d.month_name as mes,
        d.quarter_of_year as trimestre,
        d.year_number as ano,
        
        -- Métricas básicas
        count(distinct p.sk_pedido) as total_pedidos,
        count(distinct p.fk_cliente) as clientes_unicos,
        
        -- Métricas financeiras
        sum(p.valor_total_pedido) as receita_bruta,
        avg(p.valor_total_pedido) as ticket_medio,
        
        -- Métricas de valor por cliente
        sum(p.valor_total_pedido) / nullif(count(distinct p.fk_cliente), 0) as receita_por_cliente,
        
        -- Métricas de crescimento
        lag(sum(p.valor_total_pedido)) over (order by d.date_day) as receita_dia_anterior,
        lag(count(distinct p.sk_pedido)) over (order by d.date_day) as pedidos_dia_anterior
        
    from dim_date d
    left join fact_pedidos p 
        on d.date_day = date_trunc('day', p.dt_pedido)
    where d.date_day between (select min(date_trunc('day', dt_pedido)) from fact_pedidos) 
                         and (select max(date_trunc('day', dt_pedido)) from fact_pedidos)
    group by 1, 2, 3, 4, 5
),

vendas_com_metricas as (
    select
        *,
        -- Média móvel de 7 dias
        avg(receita_bruta) over (
            order by date_day
            rows between 6 preceding and current row
        ) as receita_media_7d,
        
        -- Variação dia anterior
        receita_bruta - receita_dia_anterior as variacao_dia_anterior,
        
        -- Taxa de crescimento
        case 
            when receita_dia_anterior > 0 
            then (receita_bruta - receita_dia_anterior) / receita_dia_anterior 
            else null 
        end as crescimento_receita_dia_anterior,
        
        -- Dados do mês/ano
        to_char(date_day, 'YYYY-MM') as mes_ano
    from vendas_por_dia
)

select
    vd.*,
    -- Variação percentual (já calculada na CTE anterior)
    (coalesce(vd.crescimento_receita_dia_anterior * 100, 0))::numeric(10,2) as variacao_percentual_dia_anterior,
    
    -- Comparação com o mesmo dia da semana
    lag(vd.receita_bruta, 7) over (order by vd.date_day) as receita_mesma_semana_anterior,
    
    -- Comparação com o mesmo mês do ano anterior
    lag(vd.receita_bruta, 12) over (partition by dd.month_of_year order by vd.date_day) as receita_mesmo_mes_ano_anterior,
    
    -- Sazonalidade (média dos últimos 3 anos para o mesmo mês)
    avg(vd.receita_bruta) over (
        partition by dd.month_of_year 
        order by vd.date_day 
        rows between 2 preceding and current row
    ) as media_movel_sazonal_3anos,
    
    -- Metadados
    current_timestamp as dbt_updated_at,
    '{{ run_started_at }}' as dbt_loaded_at
from vendas_com_metricas vd
left join dim_date dd on vd.date_day = dd.date_day
order by vd.date_day desc
