"""
03_test_agent.py - Interactive chat with your AI Foundry Agent

Adapted from the accelerator repo's 08_test_agent.py.
Simplified: NO SQL, NO Fabric - the agent ONLY uses Azure AI Search.
Uses the standard azure-ai-projects thread/run API (no agent_framework needed).

What this script does:
  1. Loads agent config from data/config/agent_ids.json
  2. Connects to your AI Foundry Agent via threads API
  3. Starts an interactive chat loop in your terminal
  4. The agent searches AI Search to answer your questions

Prerequisites:
  - 01_upload_to_search.py ran (created search index)
  - 02_create_agent.py ran (created the agent)

Usage:
    python 03_test_agent.py              # Normal mode
    python 03_test_agent.py -v           # Verbose (show run details)
"""

import os
import sys
import json
import re
import argparse

# Parse arguments first
parser = argparse.ArgumentParser(description="Test AI Foundry Agent with AI Search")
parser.add_argument("-v", "--verbose", action="store_true", help="Show run details")
args = parser.parse_args()

VERBOSE = args.verbose

# Load environment
from load_env import load_all_env, get_data_folder
load_all_env()

from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient

# ============================================================================
# Configuration
# ============================================================================

ENDPOINT = os.getenv("AZURE_AI_AGENT_ENDPOINT") or os.getenv("AZURE_AI_PROJECT_ENDPOINT")

if not ENDPOINT:
    print("ERROR: AZURE_AI_AGENT_ENDPOINT not set")
    print("       Run 'azd up' first")
    sys.exit(1)

# Load data folder + agent config
try:
    data_dir = get_data_folder()
except ValueError:
    print("ERROR: DATA_FOLDER not set")
    sys.exit(1)

config_dir = os.path.join(data_dir, "config")
if not os.path.exists(config_dir):
    config_dir = data_dir

agent_ids_path = os.path.join(config_dir, "agent_ids.json")
if not os.path.exists(agent_ids_path):
    print("ERROR: agent_ids.json not found")
    print("       Run 02_create_agent.py first")
    sys.exit(1)

with open(agent_ids_path) as f:
    agent_ids = json.load(f)

AGENT_ID = agent_ids.get("chat_agent_id")
AGENT_NAME = agent_ids.get("chat_agent_name", "ChatAgent")

if not AGENT_ID:
    print("ERROR: No agent ID found in agent_ids.json")
    print("       Run 02_create_agent.py first")
    sys.exit(1)

print(f"\n{'='*60}")
print("AI Agent Chat (Azure AI Search)")
print(f"{'='*60}")
print(f"Agent    : {AGENT_NAME} ({AGENT_ID})")
print(f"Endpoint : {ENDPOINT}")
print(f"\nType 'quit' to exit, 'help' for sample questions\n")

# ============================================================================
# Sample Questions
# ============================================================================

sample_questions = [
    "What are the vibration monitoring thresholds?",
    "What is the alarm priority matrix?",
    "What are the emission limits for SO2 and NOx?",
    "What are the water discharge limits?",
]

# Try to load custom questions from config
questions_path = os.path.join(config_dir, "sample_questions.txt")
if os.path.exists(questions_path):
    loaded = []
    with open(questions_path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                if line.startswith("- "):
                    loaded.append(line[2:])
                elif len(line) > 2 and line[0].isdigit() and ". " in line:
                    loaded.append(line.split(". ", 1)[1])
    if loaded:
        sample_questions = loaded


def show_help():
    print("\nSample questions to try:")
    for i, q in enumerate(sample_questions, 1):
        print(f"  {i}. {q}")
    print("\n  All questions are answered using Azure AI Search.")
    print("  Type a number to use a sample question.\n")

# ============================================================================
# Initialize Client
# ============================================================================

credential = DefaultAzureCredential()
project_client = AIProjectClient(endpoint=ENDPOINT, credential=credential)

# Create a thread (conversation) for multi-turn context
thread = project_client.agents.create_thread()
print(f"Thread created: {thread.id}")
print("-" * 60)

# ============================================================================
# Chat Function
# ============================================================================

def chat(user_message: str):
    """Send a message to the agent and print the response."""

    # Add user message to the thread
    project_client.agents.create_message(
        thread_id=thread.id,
        role="user",
        content=user_message,
    )

    # Run the agent on the thread (processes the message + tool calls)
    run = project_client.agents.create_and_process_run(
        thread_id=thread.id,
        agent_id=AGENT_ID,
    )

    if VERBOSE:
        print(f"\n  [run] status={run.status}, id={run.id}")

    if run.status == "failed":
        print(f"\nError: Agent run failed")
        if run.last_error:
            print(f"  {run.last_error.code}: {run.last_error.message}")
        return None

    # Get the latest messages (agent's response)
    messages = project_client.agents.list_messages(thread_id=thread.id)

    # The first message in the list is the most recent (agent's reply)
    for msg in messages.data:
        if msg.role == "assistant":
            # Extract text from message content
            text_parts = []
            for content_block in msg.content:
                if hasattr(content_block, "text"):
                    text = content_block.text.value
                    # Remove citation markers like [doc1] or 【4:0+source】
                    text = re.sub(r'\u3010\d+:\d+\u2020[^\u3011]+\u3011', '', text)
                    text_parts.append(text)

                    # Show citations in verbose mode
                    if VERBOSE and hasattr(content_block.text, "annotations"):
                        for ann in content_block.text.annotations:
                            if hasattr(ann, "file_citation"):
                                print(f"  [citation] {ann.text}")

            if text_parts:
                response = "\n".join(text_parts)
                print(f"\nAssistant: {response}")
                return response

            # Only print the first assistant message (most recent)
            break

    return None

# ============================================================================
# Main Chat Loop
# ============================================================================

try:
    while True:
        try:
            user_input = input("\nYou: ").strip()

            if not user_input:
                continue

            if user_input.lower() in ("quit", "exit", "q"):
                print("Goodbye!")
                break

            if user_input.lower() == "help":
                show_help()
                continue

            # Numbered shortcut for sample questions
            if user_input.isdigit():
                idx = int(user_input) - 1
                if 0 <= idx < len(sample_questions):
                    user_input = sample_questions[idx]
                    print(f"  -> {user_input}")

            chat(user_input)

        except KeyboardInterrupt:
            print("\n\nGoodbye!")
            break
        except EOFError:
            print("\nGoodbye!")
            break

finally:
    # Cleanup thread
    try:
        project_client.agents.delete_thread(thread.id)
        print("\nThread cleaned up.")
    except Exception:
        pass
