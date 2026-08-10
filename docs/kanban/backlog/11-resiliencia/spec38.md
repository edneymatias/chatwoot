### Solução 1: Escutar a reconexão do WebSocket (Automática e Transparente)

  Essa é a solução mais elegante. O Chatwoot emite um evento global chamado WEBSOCKET_RECONNECT_COMPLETED assim que ele consegue se
  reconectar ao servidor com sucesso (o que garante que a internet está 100% estável).
  Podemos adicionar um pequeno trecho de código no Index.vue das Oportunidades para escutar esse evento. Assim:

  • Se a página recarregar e a busca falhar, a tela fica vazia.
  • Mas, 1 ou 2 segundos depois, quando a internet estabilizar e o WebSocket reconectar, nosso código ouve esse evento e dispara o fetch
  novamente de forma automática.
  • A tela piscaria vazia e logo em seguida se preencheria sozinha, sem você precisar trocar de tela.

  ### Solução 2: Estado de Erro / Empty State Visual (Experiência do Usuário)

  Atualmente, se a requisição falha e o allCards ou o pipelineStages ficam vazios, o código do Vue simplesmente não desenha nada (daí a tela
  vazia cinza).
  O ideal (e uma boa prática de UX) é exibir um componente visual quando a lista estiver vazia por falha. Mostraríamos uma ilustração
  bonitinha com a mensagem: "Não foi possível carregar as oportunidades. Verifique sua conexão." e um botão "Tentar Novamente".
  Isso tiraria a sensação de que o sistema "quebrou" e daria a você um botão rápido para corrigir o problema.

  ### Solução 3: Adicionar a tela ao ReconnectService.js

  Atualmente o ReconnectService recarrega automaticamente os dados das Conversas e Notificações caso a suspensão seja menor que 3 horas.
  Podemos adicionar um gatilho para ele também forçar a atualização das Oportunidades se você estiver nessa rota. (Mas isso não resolveria
  totalmente o caso do reload das >3h na tela de bloqueio).