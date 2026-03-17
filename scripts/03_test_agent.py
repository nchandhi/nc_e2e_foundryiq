"""
03_test_agent.py — Interactive chat with your AI Foundry Agent

Adapted from the accelerator repo's 08_test_agent.py.
Simplified: NO SQL, NO Fabric — the agent ONLY uses the Knowledge Base.
No pyodbc or SQL connection needed.

What this script does:
  1. Loads agent config from data/config/agent_ids.json
  2. Connects to the AI Foundry Agent
  3. Starts an interactive chat loop in your terminal
  4. The agent searches the Knowledge Base to answer your questions

Prerequisites:
  - 01_upload_to_search.py ran (created search index + KB)
  - 02_create_agent.py ran (created the agent)

Usage:
    python 03_test_agent.py              # Normal mode
    python 03_test_agent.py -v           # Verbose (show tool calls)
    python 03_test_agent.py --agent-name MyAgent   # Specify agent name
"""

import os
import sys
import json
import re
import argparse
import asyncio
import logging
import traceback

# Parse arguments first
parser = argparse.ArgumentParser(description="Test AI Foundry Agent with Knowledge Base")
parser.add_argument("--agent-name", type=str, help="Agent name to test (default: from agent_ids.json)")
parser.add_argument("-v", "--verbose", action="store_true", help="Show detailed tool calls and results")
args = parser.parse_args()

VERBOSE = args.verbose

# Load environment
from load_env import load_all_env, get_data_folder
load_all_env()

from azure.identity.aio import DefaultAzureCredential as AsyncDefaultAzureCredential
from azure.ai.projects.aio import AIProjectClient
from agent_framework.azure import AzureAIProjectAgentProvider

# Suppress noisy framework logs unless verbose
if not VERBOSE:
    logging.getLogger("agent_framework.azure").setLevel(logging.ERROR)
    logging.getLogger("azure").setLevel(logging.WARNING)

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

CHAT_AGENT_NAME = args.agent_name or agent_ids.get("chat_agent_name")
if not CHAT_AGENT_NAME:
    print("ERROR: No agent name found")
    print("       Run 02_create_agent.py first, or use --agent-name")
    sys.exit(1)

KB_NAME = agent_ids.get("knowledge_base_name", "unknown")

print(f"\n{'='*60}")
print("AI Agent Chat (Knowledge Base)")
print(f"{'='*60}")
print(f"Agent          : {CHAT_AGENT_NAME}")
print(f"Knowledge Base : {KB_NAME}")
print(f"Endpoint       : {ENDPOINT}")
print(f"\nType 'quit' to exit, 'help' for sample questions\n")

# ============================================================================
# Sample Questions
# ============================================================================

sample_questions = [
    "What documents are in the knowledge base?",
    "What are the key policies described in the documents?",
    "Summarize the main guidelines or procedures.",
    "What thresholds or limits are defined?",
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
    print("\n  All questions are answered using the Knowledge Base.")
    print("  Type a number to use a sample question.\n")

# ============================================================================
# Chat Function
# ============================================================================

async def chat(user_message: str, conversation_id: str, agent):
    """Send a message to the agent and stream the response."""
    try:
        text_output = ""
        citations = []

        async for chunk in agent.run(user_message, stream=True, conversation_id=conversation_id):
            # Collect citations if available
            for content in getattr(chunk, "contents", []):
                annotations = getattr(content, "annotations", [])
                if annotations:
                    citations.extend(annotations)

            chunk_text = str(chunk.text) if chunk.text else ""
            # Remove citation markers like 【4:0†source】
            chunk_text = re.sub(r'【\d+:\d+†[^】]+】', '', chunk_text)
            if chunk_text:
                text_output += chunk_text

        if text_output:
            print(f"\nAssistant: {text_output}")

        # Show citations in verbose mode
        if VERBOSE and citations:
            print("\n  Citations:")
            seen = set()
            for c in citations:
                title = c.get("title", "N/A")
                if title not in seen:
                    seen.add(title)
                    url = c.get("url") or (c.get("additional_properties") or {}).get("get_url", "")
                    print(f"    - {title}" + (f": {url}" if url else ""))

        return text_output

    except Exception as e:
        print(f"\nError: {e}")
        if VERBOSE:
            traceback.print_exc()
        return None

# ============================================================================
# Main Chat Loop
# ============================================================================

async def main():
    async with (
        AsyncDefaultAzureCredential() as credential,
        AIProjectClient(endpoint=ENDPOINT, credential=credential) as project_client,
    ):
        # Get agent via provider
        provider = AzureAIProjectAgentProvider(project_client=project_client)
        agent = await provider.get_agent(name=CHAT_AGENT_NAME)

        # Create conversation for multi-turn context
        openai_client = project_client.get_openai_client()
        conversation = await openai_client.conversations.create()

        print("-" * 60)

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

                await chat(user_input, conversation.id, agent)

            except KeyboardInterrupt:
                print("\n\nGoodbye!")
                break
            except EOFError:
                print("\nGoodbye!")
                break

        # Cleanup
        try:
            await openai_client.conversations.delete(conversation_id=conversation.id)
            print("\nConversation cleaned up.")
        except Exception:
            pass


if __name__ == "__main__":
    asyncio.run(main())
