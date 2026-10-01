---
name: agendamento
title: Agendamento do lead qualificado
priority: 20
when_state:
  - opportunity_in_stage: qualified
  - contact_has_phone
  - playbook_not_completed: agendamento
trigger: >
  O lead foi qualificado e o próximo passo é agendar um atendimento.
requires: [scheduling, customer_registry]
exits:
  agendado:
    kind: terminal
    precondition: booking
  sem_horario:
    kind: terminal
    fields:
      motivo: string
---

## Fluxo de Agendamento

1. Localize o cadastro do cliente pelo telefone cadastrado chamando customer_registry_find_by_phone. Se o retorno for not_found, confirme o nome do cliente e crie o cadastro chamando customer_registry_create [[depends: customer_registry]]
2. Pergunte qual o dia de preferência para o atendimento da consulta e consulte a disponibilidade chamando scheduling_list_slots.
3. Apresente no máximo três horários disponíveis para escolha do cliente, em linguagem natural, utilizando exclusivamente horários retornados pelo sistema [[depends: scheduling]]
4. Ao confirmar a escolha do cliente, registre a reserva chamando scheduling_book com o slot_id correspondente e acione exit_agendado após a confirmação da reserva [[depends: scheduling]]
5. Se não houver horário na data solicitada, consulte a disponibilidade dos próximos dias chamando scheduling_list_slots para no máximo os três dias seguintes em ordem e ofereça a data mais próxima disponível. Se nenhuma data tiver horários disponíveis, registre exit_sem_horario informando no motivo que nenhuma disponibilidade foi encontrada; se todas as opções forem recusadas pelo cliente, registre exit_sem_horario com o motivo da recusa [[depends: scheduling]]
6. Caso o cliente solicite falar com uma pessoa, declare urgência clínica, ou após duas tentativas sem conseguir localizar o cadastro (respostas ambíguas), acione exit_handoff.
7. Se o contato não tiver telefone cadastrado, não chame ferramentas customer_registry_*, não peça o telefone ao cliente e chame exit_handoff neste mesmo turno informando a ausência do telefone. Se qualquer ferramenta retornar erro ou se a integração falhar, não repita a chamada, não prometa a reserva e chame exit_handoff neste mesmo turno.
