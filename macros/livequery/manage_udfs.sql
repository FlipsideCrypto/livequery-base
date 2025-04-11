{% macro drop_function(
        func_name,
        signature
    ) %}
    DROP FUNCTION IF EXISTS {{ func_name }}({{ compile_signature(signature, drop_ = True) }});
{% endmacro %}

{%- macro construct_api_route(route) -%}
    'https://{{ var("EXTERNAL_FUNCTION_URI") | lower }}{{ route }}'
{%- endmacro -%}

{%- macro compile_signature(
        params,
        drop_ = False
    ) -%}
    {% for p in params -%}
        {%- set name = p.0 -%}
        {%- set data_type = p.1 -%}
        {% if drop_ %}
            {{ data_type -}}
        {% else %}
            {{ name ~ " " ~ data_type -}}
        {%- endif -%}
        {%-if not loop.last -%},
        {%- endif -%}
    {% endfor -%}
{%- endmacro -%}

{% macro create_sql_function(
        name_,
        signature,
        return_type,
        sql_,
        api_integration = none,
        options = none,
        func_type = none
    ) %}
    CREATE OR REPLACE {{ func_type }} FUNCTION {{ name_ }}(
            {{- livequery_base.compile_signature(signature) }}
    )
    COPY GRANTS
    RETURNS {{ return_type }}
    {% if options -%}
        {{ options }}
    {% endif %}
    {%- if api_integration -%}
    api_integration = {{ api_integration }}
    AS {{ livequery_base.construct_api_route(sql_) ~ ";" }}
    {% else -%}
    AS
    $$
    {{ sql_ }}
    $$;
    {%- endif -%}
{%- endmacro -%}

{%- macro create_or_drop_function_from_config(
        config,
        drop_ = False
    ) -%}
    {% set name_ = config ["name"] %}
    {% set signature = config ["signature"] %}
    {% set return_type = config ["return_type"] if config ["return_type"] is string else config ["return_type"][0] %}
    {% set sql_ = config ["sql"] %}
    {% set options = config ["options"] %}
    {% set api_integration = config ["api_integration"] %}
    {% set func_type = config ["func_type"] %}

    {% if not drop_ -%}
        {{ livequery_base.create_sql_function(
            name_ = name_,
            signature = signature,
            return_type = return_type,
            sql_ = sql_,
            options = options,
            api_integration = api_integration,
            func_type = func_type
        ) }}
    {%- else -%}
        {{ drop_function(
            name_,
            signature = signature,
        ) }}
    {%- endif %}
{% endmacro %}

{% macro crud_udfs(config_func, schema, drop_) %}
{#
    Generate create or drop statements for a list of udf configs for a given schema

    config_func: function that returns a list of udf configs
    drop_: whether to drop or create the udfs
 #}
    {% set udfs = fromyaml(config_func())%}
    {%- for udf in udfs -%}
        {% if udf["name"].split(".") | first == schema %}
            CREATE SCHEMA IF NOT EXISTS {{ schema }};
            {{- create_or_drop_function_from_config(udf, drop_=drop_) -}}
        {%- endif -%}
    {%- endfor -%}
{%- endmacro -%}

{% macro crud_udfs_by_chain(config_func, blockchain, network, drop_) %}
{#
    Generate create or drop statements for a list of udf configs for a given blockchain and network

    config_func: function that returns a list of udf configs
    blockchain: blockchain name
    network: network name
    drop_: whether to drop or create the udfs
 #}
  {% set schema = blockchain if not network else blockchain ~ "_" ~ network %}
    CREATE SCHEMA IF NOT EXISTS {{ schema }};
    {%-  set configs = fromyaml(config_func(blockchain, network)) if network else fromyaml(config_func(schema, blockchain)) -%}
    {%- for udf in configs -%}
        {{- livequery_base.create_or_drop_function_from_config(udf, drop_=drop_) -}}
    {%- endfor -%}
{%- endmacro -%}

{% macro ephemeral_deploy_core(config) %}
{#
    This macro is used to deploy functions using ephemeral models.
    It should only be used within an ephemeral model.
 #}
    {% if execute and (var("UPDATE_UDFS_AND_SPS") or var("DROP_UDFS_AND_SPS")) and model.unique_id in selected_resources %}
        {% set sql %}
            {{- crud_udfs(config, this.schema, var("DROP_UDFS_AND_SPS")) -}}
        {%- endset -%}
        {%- if var("DROP_UDFS_AND_SPS") -%}
            {%- do log("Drop core udfs: " ~ this.database ~ "." ~ this.schema, true) -%}
        {%- else -%}
            {%- do log("Deploy core udfs: " ~ this.database ~ "." ~ this.schema, true) -%}
        {%- endif -%}
        {%- do run_query(sql ~ apply_grants_by_schema(this.schema)) -%}
    {%- endif -%}
    SELECT '{{ model.schema }}' as schema_
{%- endmacro -%}

{% macro ephemeral_deploy(configs) %}
{#
    This macro is used to deploy functions using ephemeral models.
    It should only be used within an ephemeral model.
 #}
    {%- set blockchain = this.schema -%}
    {%- set network = this.identifier -%}
    {% set schema = blockchain ~ "_" ~ network %}
    {% if execute and (var("UPDATE_UDFS_AND_SPS") or var("DROP_UDFS_AND_SPS")) and model.unique_id in selected_resources %}
        {% set sql %}
            {% for config in configs %}
                {{- livequery_base.crud_udfs_by_chain(config, blockchain, network, var("DROP_UDFS_AND_SPS")) -}}
            {%- endfor -%}
        {%- endset -%}
        {%- if var("DROP_UDFS_AND_SPS") -%}
            {%- do log("Drop partner udfs: " ~ this.database ~ "." ~ schema, true) -%}
        {%- else -%}
            {%- do log("Deploy partner udfs: " ~ this.database ~ "." ~ schema, true) -%}
        {%- endif -%}
        {%- do run_query(sql ~ livequery_base.apply_grants_by_schema(schema)) -%}
    {%- endif -%}
    SELECT '{{ model.schema }}' as schema_
{%- endmacro -%}


