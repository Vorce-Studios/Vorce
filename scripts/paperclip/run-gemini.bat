@echo off
rem run-gemini.bat - wrapper for paperclip process adapter
rem Usage: run-gemini.bat <roleKey> <instructionPath> <policyRoot>
set ROLE_KEY=%1
set INSTR_PATH=%2
set POLICY_ROOT=%3
set VORCE_STUDIOS_ROLE=%1

gemini -y -p "You are an AI agent for Vorce-Studios with roleKey=%1. Your instructions are at %2. Your policies are at %3. Read both files carefully and follow them."
