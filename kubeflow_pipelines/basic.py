from kfp import dsl


@dsl.component
def say_hello(name: str) -> str:
    hello_text = f"Hello, {name}!"
    print(hello_text)
    return hello_text


@dsl.pipeline
def hello_pipeline(recipient: str) -> str:
    hello_task = say_hello(name=recipient)
    return hello_task.output


from kfp import compiler

compiler.Compiler().compile(hello_pipeline, "pipeline.yaml")

from kfp.client import Client

client = Client(host="http://localhost:8080")
run = client.create_run_from_pipeline_package(
    "pipeline.yaml",
    arguments={
        "recipient": "World",
    },
)
