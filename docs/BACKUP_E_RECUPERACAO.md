# Backup e recuperação

Os dados operacionais do Tudo Aqui Macacu ficam no Cloud Firestore do projeto
`todo-aqui-macacu`. O aplicativo não é a fonte oficial dos dados.

## Rotina recomendada

Antes de alterações grandes, exporte os dados pelo Console do Google Cloud e
guarde uma cópia com data e responsável. Faça isso também antes de publicar a
primeira base de estabelecimentos, anúncios e dados comerciais reais.

## Recuperação

Uma restauração deve ser feita apenas após confirmar o conteúdo do backup e o
impacto nos dados criados depois dele. Primeiro restaure em um projeto de teste;
depois valide estabelecimentos, anúncios, usuários e regras antes de usar em
produção.

## Limitação atual

O projeto está no plano Spark. Exportações automáticas e agendadas exigem uma
configuração de infraestrutura paga no Google Cloud. Até essa decisão, a rotina
é manual e deve ser registrada neste repositório ou em uma planilha operacional.
