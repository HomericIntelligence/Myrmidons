#!/usr/bin/env python3
"""Hello World Myrmidon — E2E test worker demonstrating the pull-based myrmidon pattern."""

import asyncio
import json
import logging
import os
from datetime import datetime, timezone

import nats
from nats.js.api import StreamConfig, ConsumerConfig, AckPolicy, DeliverPolicy

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
log = logging.getLogger("hello-myrmidon")

NATS_URL = os.environ.get("NATS_URL", "nats://localhost:4222")
STREAM_NAME = "homeric-myrmidon"
CONSUMER_NAME = "hello-myrmidon"
SUBJECT_FILTER = "hi.myrmidon.hello.>"


async def main():
    log.info(f"Hello Myrmidon starting, connecting to NATS at {NATS_URL}")

    # Connect to NATS
    nc = await nats.connect(NATS_URL)
    js = nc.jetstream()

    log.info("Connected to NATS")

    # Ensure stream exists (idempotent)
    try:
        await js.add_stream(StreamConfig(name=STREAM_NAME, subjects=["hi.myrmidon.>"]))
        log.info(f"Created stream {STREAM_NAME}")
    except Exception as e:
        if "already in use" in str(e).lower() or "exists" in str(e).lower():
            log.info(f"Stream {STREAM_NAME} already exists")
        else:
            log.warning(f"Stream creation warning: {e}")

    # Create durable pull consumer
    try:
        await js.add_consumer(
            STREAM_NAME,
            ConsumerConfig(
                name=CONSUMER_NAME,
                durable_name=CONSUMER_NAME,
                filter_subject=SUBJECT_FILTER,
                ack_policy=AckPolicy.EXPLICIT,
                deliver_policy=DeliverPolicy.ALL,
                max_ack_pending=1,  # Rate limiting: 1 in-flight at a time
            )
        )
        log.info(f"Created consumer {CONSUMER_NAME}")
    except Exception as e:
        if "already in use" in str(e).lower() or "exists" in str(e).lower():
            log.info(f"Consumer {CONSUMER_NAME} already exists")
        else:
            log.warning(f"Consumer creation warning: {e}")

    # Get pull subscription
    psub = await js.pull_subscribe(SUBJECT_FILTER, durable=CONSUMER_NAME)

    log.info(f"Listening for tasks on {SUBJECT_FILTER} (MaxAckPending=1)")

    while True:
        try:
            msgs = await psub.fetch(1, timeout=5)
            for msg in msgs:
                await process_task(js, msg)
        except nats.errors.TimeoutError:
            # No messages available, keep polling
            continue
        except Exception as e:
            log.error(f"Error fetching messages: {e}")
            await asyncio.sleep(1)


async def process_task(js, msg):
    try:
        task_data = json.loads(msg.data.decode())
        task_id = task_data.get("task_id", "unknown")
        team_id = task_data.get("team_id", "unknown")
        subject = task_data.get("subject", "unknown task")

        log.info(f"Processing task {task_id}: {subject}")

        # Simulate work
        await asyncio.sleep(1)

        now = datetime.now(timezone.utc).isoformat()

        # Publish completion event to hi.tasks.{team_id}.{task_id}.completed
        completion_subject = f"hi.tasks.{team_id}.{task_id}.completed"
        completion_payload = json.dumps({
            "event": "task.completed",
            "data": {
                "team_id": team_id,
                "task_id": task_id,
                "result": "Hello World! Task processed successfully.",
                "status": "completed"
            },
            "timestamp": now
        }).encode()

        await js.publish(completion_subject, completion_payload)
        log.info(f"Published completion to {completion_subject}")

        # Publish log to hi.logs.myrmidon.hello
        log_payload = json.dumps({
            "level": "info",
            "service": "hello-myrmidon",
            "message": f"Completed task {task_id}: {subject}",
            "task_id": task_id,
            "team_id": team_id,
            "timestamp": now
        }).encode()

        try:
            await js.publish("hi.logs.myrmidon.hello", log_payload)
        except Exception as e:
            log.warning(f"Failed to publish log: {e}")

        # Ack the message
        await msg.ack()
        log.info(f"Task {task_id} completed and acknowledged")

    except Exception as e:
        log.error(f"Error processing task: {e}")
        await msg.nak()


if __name__ == "__main__":
    asyncio.run(main())
