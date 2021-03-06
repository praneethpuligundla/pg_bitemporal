CREATE OR REPLACE FUNCTION bitemporal_internal.ll_bitemporal_list_of_fields(p_table text) RETURNS text[]
AS
$BODY$
BEGIN
RETURN ( array(SELECT attname
                          FROM (SELECT * FROM pg_attribute
                                  WHERE attrelid=p_table::regclass AND attnum >0) pa
                          LEFT OUTER JOIN pg_attrdef pad ON adrelid=p_table::regclass
                                                        AND adrelid=attrelid
                                                        AND pa.attnum=pad.adnum
                          WHERE (adsrc NOT LIKE 'nextval%' OR adsrc IS NULL)
                                AND attname !='asserted'
                                AND attname !='effective'
                                AND attname !='row_created_at'
                                and attname not like '%dropped%'
                        ORDER BY pa.attnum));
END;                        
$BODY$ LANGUAGE plpgsql;


