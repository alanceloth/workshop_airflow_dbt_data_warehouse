{{
    config(
        materialized = 'table',
        unique_key = 'sk_cliente',
        tags = ['intermediate', 'dimension']
    )
}}

with clientes as (
    select * from {{ ref('stg_cadastros') }}
)

select
    -- Chave substituta (surrogate key)
    {{ dbt_utils.generate_surrogate_key(['cpf']) }} as sk_cliente,
    
    -- Chave de negócio
    cpf,
    
    -- Atributos descritivos
    nome,
    email,
    estado,
    cidade,
    dt_nascimento,
    
    -- Datas importantes
    dt_cadastro,
    
    -- Metadados
    current_timestamp as dbt_updated_at,
    '{{ run_started_at }}' as dbt_loaded_at
from clientes