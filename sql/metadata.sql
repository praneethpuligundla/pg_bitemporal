-- 
--
--  triggers, not null, exclusions and check 
-- all work exactly the same given the bitemporal constraints
--
-- 3 constraints do not. primary key, foreign key and unique constraints.
--

-- create the three types of constraints.
--   need strings to include in a create table
--   need commands to modify existing table

-- find the a particular set of constraints given a table
-- 

create or replace 
function bitemporal_conname_prefix() returns text
language sql IMMUTABLE as $f$ 
    select 'bitemporal'::text;
$f$;

create or replace 
function mk_conname(con_type text, src_column text, fk_table text, fk_column text ) 
returns text
language sql IMMUTABLE
as $f$ 
select substring(format('%s %s %s%s%s', bitemporal_conname_prefix()
                   , con_type
                   , src_column
                   , fk_table, fk_column)
          from 0 for 64 );
$f$;

create or replace 
function mk_constraint(con_type text, con_name text, con_src text) 
returns text
language sql IMMUTABLE
as $ff$ 
  select format($$CONSTRAINT %I check(true or '%s' <> '@%s@') $$
        , con_name 
        , con_type
        , con_src)::text;
$ff$;

create or replace 
function pk_constraint(src_column text) 
returns text
language sql IMMUTABLE as $f$ 
  select mk_constraint('pk', mk_conname('pk', src_column, '', '') , src_column);
$f$;

create or replace 
function fk_constraint(src_column text, fk_table text, fk_column text) 
returns text
language sql IMMUTABLE
as $ff$ 
  select mk_constraint('fk'
             , mk_conname('fk', src_column, fk_table, fk_column)
             , format('%s -> %s(%s)', src_column, fk_table, fk_column) ); 
$ff$;

create or replace 
function unique_constraint(src_column text) 
returns text
language sql IMMUTABLE
as $f$ 
  select format('CONSTRAINT %I EXCLUDE USING gist 
                (%I WITH =, asserted WITH &&, effective WITH &&)'
            , mk_conname('unique', src_column, '', '')
            , src_column)::text;
--   CONSTRAINT devices_device_id_asserted_effective_excl EXCLUDE 
--  USING gist (device_id WITH =, asserted WITH &&, effective WITH &&)
$f$;

create or replace 
function add_constraint(table_name text, _con text) 
returns text
language sql IMMUTABLE
as $f$ 
  select format('alter table %s add %s', table_name, _con)::text; 
$f$;

create or replace 
function select_constraint_value(src text) 
returns  text
language plpgsql IMMUTABLE
as $f$ 
DECLARE 
  at int;
  s   text;
BEGIN
-- select inside @ @
  at := strpos(src, '@');
  s  := substr(src, at + 1 );
  at := strpos(s, '@');
  return substring(s from 0::int for at );
END;
$f$;

create or replace 
function find_bitemporal_constraints(table_name text, _criteria text ) 
returns setof pg_constraint
language sql IMMUTABLE
as $f$ 
    select *
       from pg_constraint 
       where conrelid = cast(table_name as regclass)
       and conname like format('%s %s %%', bitemporal_conname_prefix(), _criteria ) 
       ;
$f$;

create or replace 
function find_bitemporal_pk(table_name text) 
returns text
language plpgsql IMMUTABLE
as $f$ 
DECLARE
    r  record;
BEGIN
    select * into r from find_bitemporal_constraints(table_name, 'pk');
    RETURN select_constraint_value(r.consrc);
END;
$f$;

create table if not exists bitemporal_fk_constraint_type (
   conname name
  , src_column  name
  , fk_table text 
  , fk_column name
);

create or replace 
function split_out_bitemporal_fk(consrc text) 
returns bitemporal_fk_constraint_type
language plpgsql IMMUTABLE
as $f$ 
DECLARE
    src text; 
    ref text; 
    rc  bitemporal_fk_constraint_type%ROWTYPE;
    rp int;
    lp int;
BEGIN
    -- format('%s -> %s(%s)', src_column, fk_table, fk_column) 
    src := select_constraint_value(consrc) ;
    rc.src_column :=  split_part(src, ' ', 1);
    ref := split_part(src, ' ', 3);
    rp := strpos(ref, '(');
    lp := strpos(ref, ')');
    if (lp < 1 or rp < 1 ) then
      raise notice 'split_out_bitemporal_fk: invaild format "%"', consrc ;
      return NULL;
    end if;
    rc.fk_table := substring(ref from 0 for rp );
    rc.fk_column :=  substring(ref from rp +1 for (lp - rp -1) );
    RETURN rc;
END;
$f$;

create or replace
function find_bitemporal_fk(table_name text) 
returns setof bitemporal_fk_constraint_type
language plpgsql
as $f$ 
DECLARE
    rc  bitemporal_fk_constraint_type%ROWTYPE;
    r record;
BEGIN
    
    for r in select * from find_bitemporal_constraints(table_name, 'fk') 
    loop
        rc := split_out_bitemporal_fk(r.consrc); 
        rc.conname := r.conname;
        return next  rc;
    end loop;
    RETURN ;
END;
$f$;



/*
       conname       | contype | conrelid |
consrc                                          
---------------------+---------+----------+-----------------------------------------------------------------------------------------
 bitemporal fk 1     | c       |  1625561 | (true OR ('fk'::text <> '@node_id -> sg.networks network_id@'::text))
 bitemporal fk 2     | c       |  1625561 | (true OR ('fk'::text = ANY (ARRAY['node_id'::text, 'cnu.networks'::text, 'id'::text])))
 bitemporal unique 3 | c       |  1625561 | (true OR ('col'::text = 'name'::text))

*/

-- vim: set filetype=pgsql expandtab tabstop=2 shiftwidth=2:
