{% test test_udf(model, column_name, args, assertions) %}
    {#
        This is a generic test for UDFs.
        The udfs are deployed using ephemeral models, as of dbt-core > 1.8
        we need to use `this.identifier` get schema.udf to test the udf.
     #}
    
    {% set schema = none %}
    
    {# Try to extract schema from 'this' when executing #}
    {% if execute %}
        {# Extract schema based on standard pattern #}
        {% set test_identifier = this.identifier %}
        
        {% if test_identifier.startswith('test_') %}
            {% set test_identifier = test_identifier[5:] %}
        {% endif %}
        
        {# Handle schemas with underscore prefix #}
        {% if test_identifier.startswith('_') %}
            {# For identifiers like _utils_<test_name> #}
            {% set parts = test_identifier.split('_') %}
            {% if parts | length > 2 %}
                {# Reconstruct schema with underscore prefix #}
                {% set schema = '_' ~ parts[1] %}
            {% else %}
                {# Fallback for simple cases #}
                {% set schema = parts[0] %}
            {% endif %}
        {% else %}
            {# For identifiers without underscore prefix #}
            {% set parts = test_identifier.split('_') %}
            {% if parts | length > 0 %}
                {% set schema = parts[0] %}
            {% endif %}
        {% endif %}
    {% endif %}
    
    {% set udf = schema ~ "." ~ column_name %}

    {{ base_test_udf(model, udf, args, assertions) }}
{% endtest %}