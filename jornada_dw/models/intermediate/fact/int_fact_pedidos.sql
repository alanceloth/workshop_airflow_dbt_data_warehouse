{{
    config(
        materialized = 'table',
        unique_key = 'sk_pedido',
        tags = ['intermediate', 'fact']
    )
}}

with pedidos as (
    select * from {{ ref('stg_pedidos') }}
),

dim_clientes as (
    select sk_cliente, cpf from {{ ref('int_dim_clientes') }}
),

dim_date as (
    select date_day from {{ ref('int_dim_date') }}
)

select
    -- Chave substituta
    {{ dbt_utils.generate_surrogate_key(['p.id_pedido']) }} as sk_pedido,
    
    -- Chaves estrangeiras
    dc.sk_cliente as fk_cliente,
    
    -- Chave de negócio
    p.id_pedido,
    
    -- Dimensões de data/hora
    p.dt_pedido,
    date_trunc('day', p.dt_pedido) as data_pedido,
    
    -- Métricas
    p.valor_total_pedido,
    
    -- Metadados
    current_timestamp as dbt_updated_at,
    '{{ run_started_at }}' as dbt_loaded_at
from pedidos p
left join dim_clientes dc on p.cpf = dc.cpf
left join dim_date dd on date_trunc('day', p.dt_pedido) = dd.date_day

