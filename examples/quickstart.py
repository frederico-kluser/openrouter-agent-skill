#!/usr/bin/env python3
# ============================================================================
# quickstart.py — API OpenRouter com o SDK oficial da OpenAI
#
# O OpenRouter é 100% compatível com o formato da API OpenAI: basta apontar
# o cliente para a base_url https://openrouter.ai/api/v1 e usar a chave
# OpenRouter. Sem dependências além do pacote `openai`:
#
#     pip install openai
#
# A chave vem da variável de ambiente OPENROUTER_API_KEY (nunca embutida).
# Sem chave, o script roda em modo dry-run (mensagem + saída 0).
#
# Fonte factual: docs/research/openrouter-api.md (seção 4, compatibilidade).
# ============================================================================
import os

try:
    from openai import OpenAI
except ImportError:
    print("Dependência ausente: instale o SDK OpenAI com:  pip install openai")
    raise SystemExit(1)

API_KEY = os.environ.get("OPENROUTER_API_KEY")
if not API_KEY:
    print("Modo dry-run: OPENROUTER_API_KEY não está definida.")
    print("  Para executar de verdade, crie uma chave em https://openrouter.ai/keys e")
    print("  exporte:  export OPENROUTER_API_KEY=sk-or-v1-...")
    raise SystemExit(0)

# base_url = OpenRouter; api_key = chave do OpenRouter (não da OpenAI).
# Os headers opcionais de atribuição (HTTP-Referer / X-OpenRouter-Title)
# alimentam os rankings do site.
client = OpenAI(
    base_url="https://openrouter.ai/api/v1",
    api_key=API_KEY,
    default_headers={
        "HTTP-Referer": "https://example.com",  # seu site (rankings)
        "X-OpenRouter-Title": "quickstart.py",  # nome do app (rankings)
    },
)

# Parâmetros extras do OpenRouter (provider, models, plugins, reasoning...)
# vão via extra_body — ex.:
# extra_body={"provider": {"only": ["openai"], "allow_fallbacks": False}}
completion = client.chat.completions.create(
    model="openai/gpt-4o",
    messages=[
        {"role": "user", "content": "Explique o que é o OpenRouter em uma frase."}
    ],
)

print(completion.choices[0].message.content)
print()

usage = completion.usage
print(f"usage: prompt_tokens={usage.prompt_tokens} "
      f"completion_tokens={usage.completion_tokens} "
      f"total_tokens={usage.total_tokens}")
# Campos extras do OpenRouter no objeto usage:
print(f"cost: ${getattr(usage, 'cost', 'indisponível')}")
if getattr(usage, "completion_tokens_details", None) is not None:
    print(f"reasoning_tokens: {getattr(usage.completion_tokens_details, 'reasoning_tokens', 0)}")
if getattr(usage, "cost_details", None) is not None:
    print(f"cost_details: {usage.cost_details}")

# Streaming também funciona: stream=True + iteração sobre completion.
#   stream = client.chat.completions.create(model="openai/gpt-4o",
#       messages=[...], stream=True)
#   for chunk in stream:
#       print(chunk.choices[0].delta.content or "", end="")
