"""make llm-hello: one call to the parser's model on Bedrock, with your own AWS credentials."""

from app.ai.agenda import PARSER_MODEL, client, runtime

QUESTION = "In one sentence: what is an ISO week?"
if PARSER_MODEL.startswith("anthropic."):
    # The Anthropic Messages API, served by Bedrock (bedrock-mantle).
    msg = client().messages.create(
        model=PARSER_MODEL,
        max_tokens=1024,
        output_config={"effort": "low"},  # short, cheap answers
        messages=[{"role": "user", "content": QUESTION}],
    )
    print(next(b.text for b in msg.content if b.type == "text"))
    print(msg.stop_reason, msg.usage.input_tokens, msg.usage.output_tokens)
else:
    # The Converse API: the same question to Amazon Nova (or any other Bedrock model).
    resp = runtime().converse(
        modelId=PARSER_MODEL,
        messages=[{"role": "user", "content": [{"text": QUESTION}]}],
        inferenceConfig={"maxTokens": 200},
    )
    print(resp["output"]["message"]["content"][0]["text"])
    print(resp["stopReason"], resp["usage"]["inputTokens"], resp["usage"]["outputTokens"])
