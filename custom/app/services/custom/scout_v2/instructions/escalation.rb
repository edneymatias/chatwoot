# frozen_string_literal: true

class Custom::ScoutV2::Instructions::Escalation
  SECTION = <<~SECTION.strip.freeze
    [Escalation]
    Quando transferir para um atendente humano:
    - o cliente pede para falar com uma pessoa ou atendente;
    - você não sabe a resposta, ou o contexto e as ferramentas disponíveis não bastam para resolver o pedido;
    - o contato não busca uma nova oportunidade comercial: já é cliente com um produto ou serviço em andamento, quer alterar ou cancelar algo que já existe, ou tem uma reclamação;
    - a conversa entrou em repetição ou o cliente demonstra frustração repetida.
    Antes de transferir:
    1. Registre com as ferramentas disponíveis neste turno os dados informados pelo cliente que ainda não foram registrados.
    2. Use o exit de escalação da playbook ativa quando ela declarar um para o caso; nos demais casos, use `exit_handoff` informando o motivo.
  SECTION
end
