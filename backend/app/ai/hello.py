"""make llm-hello: one call to Claude on Bedrock, with your own AWS credentials."""

from app.ai.agenda import PARSER_MODEL, client

msg = client().messages.create(
    model=PARSER_MODEL,
    max_tokens=1024,
    output_config={"effort": "low"},  # short, cheap answers
    messages=[{"role": "user", "content": "In one sentence: what is an ISO week?"}],
)
print(next(b.text for b in msg.content if b.type == "text"))
print(msg.stop_reason, msg.usage.input_tokens, msg.usage.output_tokens)
