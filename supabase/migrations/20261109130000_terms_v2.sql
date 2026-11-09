-- =====================================================================
-- Podmínky a zásady z 9. 11. 2026: výslovný souhlas se zdravotními údaji
-- (zaškrtávátko v appce), „o co se hraje“ místo sázek, odpovědnost, Apple.
-- Nová verze → appka všem členům jednou ukáže TermsUpdateView.
-- Záznam v terms_acceptances s touto verzí = souhlas s podmínkami, zásadami
-- i výslovný souhlas se zpracováním spánku a tepu (čl. 9 odst. 2 písm. a GDPR).
-- =====================================================================

create or replace function private.terms_version()
returns text language sql immutable set search_path = '' as $$
  select '2026-11-09';
$$;
