-- =====================================================================
--  CONTROL DE ACTIVIDADES  ·  Esquema Supabase
--  Pegar completo en: Supabase > SQL Editor > New query > RUN
-- =====================================================================
create extension if not exists pgcrypto;

-- Todas las tablas comparten la misma forma: id + documento JSON.
-- users      trabajadores / conductores / auxiliares / admins
-- rooms      habitaciones (estado, asignación, cronómetro)
-- cleanings  histórico de tiempos de aseo
-- tasks      tareas de mantenimiento y sistemas
-- works      obras civiles + cronograma
-- catalog    tipos de tarea y tipos de equipo (editables)
-- notifs     notificaciones/alertas   · chat  mensajes admin <-> admin mant.
-- routes     rutas de entrega         · invoices facturas de cada ruta
-- geo        coordenadas OCULTAS de cada entrega (solo las consulta el admin)
-- live       posición en vivo del vehículo

do $$
declare t text;
begin
  foreach t in array array['users','rooms','cleanings','tasks','works','catalog',
                           'notifs','chat','routes','invoices','geo','live']
  loop
    execute format('create table if not exists public.%I (
        id text primary key,
        data jsonb not null default ''{}''::jsonb,
        created_at timestamptz not null default now(),
        updated_at timestamptz not null default now())', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "app_all" on public.%I', t);
    execute format('create policy "app_all" on public.%I for all to anon, authenticated using (true) with check (true)', t);
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

create index if not exists invoices_route_idx on public.invoices ((data->>'routeId'));
create index if not exists users_username_idx on public.users ((lower(data->>'user')));
create index if not exists cleanings_day_idx  on public.cleanings ((data->>'day'));

-- updated_at automático
create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
do $$
declare t text;
begin
  foreach t in array array['users','rooms','cleanings','tasks','works','catalog',
                           'notifs','chat','routes','invoices','geo','live']
  loop
    execute format('drop trigger if exists trg_touch on public.%I', t);
    execute format('create trigger trg_touch before update on public.%I for each row execute function public.touch_updated_at()', t);
  end loop;
end $$;

-- Login validado en la base de datos (devuelve el usuario o null)
create or replace function public.app_login(p_user text, p_pin text)
returns jsonb language sql security definer set search_path = public as $$
  select jsonb_build_object('id', id) || data - 'pin'
  from public.users
  where lower(data->>'user') = lower(trim(p_user))
    and data->>'pin' = p_pin
    and coalesce((data->>'active')::boolean, true)
  limit 1
$$;
grant execute on function public.app_login(text, text) to anon, authenticated;

-- ---------------------------- Datos iniciales ------------------------
insert into public.users (id, data) values
 ('admin', '{"name":"Administrador General","user":"admin","pin":"1234","role":"admin","active":true}'),
 ('jefe',  '{"name":"Jefe de Mantenimiento","user":"jefe","pin":"1234","role":"maint_admin","active":true}'),
 ('entregas','{"name":"Administrador de Entregas","user":"entregas","pin":"1234","role":"deliv_admin","active":true}')
on conflict (id) do nothing;

insert into public.catalog (id, data) values
 ('types', '{"items":["Pintura","Arreglo y mantenimiento de equipo","Jardinería","Obra civil","Eléctrico","Plomería","Sistemas / Soporte"]}'),
 ('equip', '{"items":["Aire acondicionado","Bomba de agua","Planta eléctrica","Nevera","Computador","Red / WiFi","Impresora","Otro"]}')
on conflict (id) do nothing;
