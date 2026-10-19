-- Sincronización de Vault entre dispositivos.
-- Una sola tabla genérica: cada fila es un deck, una carta de deck, una carta de colección o un deseo.
create table if not exists public.sync_records (
  user_id    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  kind       text        not null check (kind in ('deck', 'deckEntry', 'collectionItem', 'wishlistItem')),
  id         text        not null,
  payload    text        not null default '{}',
  deleted    boolean     not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, kind, id)
);

create index if not exists sync_records_user_updated_idx on public.sync_records (user_id, updated_at);

-- La hora la pone el servidor, así no importa si el reloj de un dispositivo está mal.
create or replace function public.sync_records_touch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists sync_records_touch on public.sync_records;
create trigger sync_records_touch
before insert or update on public.sync_records
for each row execute function public.sync_records_touch();

-- Cada quien solo ve y toca sus propias filas.
alter table public.sync_records enable row level security;

drop policy if exists "sync_records_select_own" on public.sync_records;
create policy "sync_records_select_own" on public.sync_records
  for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "sync_records_insert_own" on public.sync_records;
create policy "sync_records_insert_own" on public.sync_records
  for insert to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists "sync_records_update_own" on public.sync_records;
create policy "sync_records_update_own" on public.sync_records
  for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists "sync_records_delete_own" on public.sync_records;
create policy "sync_records_delete_own" on public.sync_records
  for delete to authenticated using ((select auth.uid()) = user_id);

-- Permisos explícitos: el proyecto no expone tablas nuevas automáticamente.
-- Solo usuarios con sesión pueden tocar la tabla, y RLS limita a sus propias filas.
revoke all on public.sync_records from anon;
grant select, insert, update, delete on public.sync_records to authenticated;
