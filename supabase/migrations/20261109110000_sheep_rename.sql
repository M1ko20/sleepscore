-- Duše → ovečky (jen texty, které vidí uživatel). Interní názvy (pohled
-- `souls`, klíč `souls`, kód `first_soul`) zůstávají.

update public.achievements set name = 'První ovečka' where code = 'first_soul';
update public.achievements set name = 'Pastýř', description = '10 získaných oveček' where code = 'collector';

create or replace function public.notification_text(n public.notifications)
returns text language plpgsql stable security invoker set search_path = '' as $$
declare
  v_actor text;
  v_name  text;
  v_score smallint;
  v_card  boolean;
  p       jsonb := n.payload;
  v_num   text;
  v_other int;
  v_cnt   int;
  v_a     numeric;
  v_b     numeric;
  v_fmt   text;
begin
  select display_name into v_actor from public.profiles where id = n.actor_id;
  v_actor := coalesce(v_actor, 'Někdo');

  case n.kind
  when 'reaction' then
    v_other := n.count - 1;
    if v_other <= 0 then
      return v_actor || ' reaguje na tvoji noc.';
    end if;
    return v_actor || ' a ' || v_other
           || case when v_other <= 4 then ' další' else ' dalších' end
           || ' reagují na tvoji noc.';

  when 'comment' then
    if not coalesce((p ->> 'thread')::boolean, false) then
      return v_actor || ' komentuje tvoji noc: ' || coalesce(p ->> 'text', '');
    end if;
    if coalesce((p ->> 'by_owner')::boolean, false) then
      return v_actor || ' odpovídá pod svojí nocí: ' || coalesce(p ->> 'text', '');
    end if;
    -- bez jména autora karty (skloňování); příjemce kartu zná, sám pod ní psal
    return v_actor || ' taky komentuje noc, pod kterou píšeš: ' || coalesce(p ->> 'text', '');

  when 'friend_request' then
    return v_actor || ' ti posílá žádost o přátelství.';

  when 'friend_accepted' then
    if (p ->> 'via_invite')::boolean then
      return v_actor || ' je tu přes tvoji pozvánku.';
    end if;
    return v_actor || ' přijímá žádost o přátelství.';

  when 'challenge_invite' then
    return v_actor
      || case p ->> 'type'
           when 'duel' then ' tě vyzývá: '
           when 'free_for_all' then ' tě zve do výzvy všichni proti všem: '
           else ' tě zve do společného cíle ' || (p ->> 'target_score') || ': '
         end
      || (p ->> 'duration_days') || ' dní'
      || coalesce(', ' || (p ->> 'stake'), '') || '.';

  when 'challenge_response' then
    if (p ->> 'accepted')::boolean then
      return v_actor || ' jde do toho.';
    end if;
    return v_actor || ' výzvu odmítá.';

  when 'challenge_started' then
    if p ->> 'type' = 'duel' and n.actor_id is not null then
      return v_actor || ' výzvu přijímá. Start ' || to_char((p ->> 'start_date')::date, 'FMDD. FMMM.')
             || ', ' || (p ->> 'duration_days') || ' dní.';
    end if;
    return 'Výzva startuje ' || to_char((p ->> 'start_date')::date, 'FMDD. FMMM.')
           || ', ' || (p ->> 'duration_days') || ' dní' || coalesce(', ' || (p ->> 'stake'), '') || '.';

  when 'challenge_overtaken' then
    v_a := (p ->> 'actor_avg')::numeric;
    v_b := (p ->> 'my_avg')::numeric;
    -- na 1 desetinné místo by vyšlo stejně → ukázat 2
    v_fmt := case when round(v_a, 1) = round(v_b, 1) then 'FM990.00' else 'FM990.0' end;
    return v_actor || ' tě předbíhá '
           || case when p ->> 'type' = 'duel' then 'v souboji' else 've výzvě' end || '. '
           || replace(to_char(v_a, v_fmt), '.', ',') || ' : ' || replace(to_char(v_b, v_fmt), '.', ',') || '.';

  when 'challenge_ending' then
    v_num := replace(to_char(abs((p ->> 'diff')::numeric), 'FM990.0'), '.', ',');
    return 'Zítra konec. ' || case p ->> 'mode'
      when 'lead'  then 'Vedeš o ' || v_num || ' bodu.'
      when 'trail' then 'Prohráváš o ' || v_num || ' bodu.'
      when 'tie'   then 'Je to nastejno.'
      else 'Skupina má ' || replace(to_char((p ->> 'avg')::numeric, 'FM990.0'), '.', ',')
           || ', cíl je ' || (p ->> 'target_score') || '.'
    end;

  when 'challenge_result' then
    v_num := replace(to_char((p ->> 'my_avg')::numeric, 'FM990.0'), '.', ',')
             || ' : ' || replace(to_char((p ->> 'other_avg')::numeric, 'FM990.0'), '.', ',');
    if p ->> 'type' = 'team_goal' then
      return case when p ->> 'result' = 'win' then 'Cíl splněn. ' else 'Cíl nesplněn. ' end
             || 'Skupina ' || replace(to_char((p ->> 'my_avg')::numeric, 'FM990.0'), '.', ',')
             || ', cíl ' || (p ->> 'target_score') || '.';
    end if;
    case p ->> 'result'
    when 'win' then
      v_cnt := coalesce((p ->> 'souls')::int, 1);
      if v_cnt > 1 then
        return 'Vyhráno ' || v_num || '. Bereš ' || v_cnt
               || case when v_cnt <= 4 then ' ovečky.' else ' oveček.' end;
      end if;
      return 'Vyhráno ' || v_num || '. ' || v_actor || ' přichází o ovečku.';
    when 'loss' then
      if p ->> 'other_result' = 'win' then
        return 'Prohra ' || v_num || '. ' || v_actor || ' bere tvoji ovečku.';
      end if;
      return 'Prohra ' || v_num || '.';   -- nahoře remíza, ovečky nikdo
    else
      return 'Remíza ' || v_num || '.';
    end case;

  when 'debt_settled' then
    return v_actor || ' hlásí splaceno: ' || coalesce(p ->> 'stake', 'sázka') || '.';

  when 'achievement' then
    select name into v_name from public.achievements where code = p ->> 'code';
    v_name := coalesce(v_name, p ->> 'code');
    if coalesce((p ->> 'times')::int, 1) > 1 then
      return v_name || '. Zase.';
    end if;
    return 'Nový odznak: ' || v_name || '.';

  when 'night_ready' then
    select ni.score, (po.title is not null or po.body is not null)
      into v_score, v_card
    from public.posts po join public.nights ni on ni.id = po.night_id
    where po.id = n.post_id;
    if v_score is null then return 'Noc je tady.'; end if;
    return 'Tvoje noc: ' || v_score || '.' || case when v_card then '' else ' Doplň komentář.' end;

  when 'weekly_recap' then
    v_cnt := (p ->> 'nights')::int;
    return 'Minulý týden v číslech: průměr '
           || replace(to_char((p ->> 'avg_score')::numeric, 'FM990'), '.', ',') || ', '
           || v_cnt || case when v_cnt = 1 then ' noc.' when v_cnt <= 4 then ' noci.' else ' nocí.' end;

  else
    return '';
  end case;
end;
$$;
revoke execute on function public.notification_text(public.notifications) from public, anon;
grant execute on function public.notification_text(public.notifications) to authenticated, service_role;
