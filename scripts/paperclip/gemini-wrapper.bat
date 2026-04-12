@echo off
rem gemini-wrapper.bat - wrapper for Paperclip process adapter
rem Usage: gemini-wrapper.bat <roleKey> <instructionPath> <policyRoot>
set VORCE_STUDIOS_ROLE=%1
gemini --prompt "You are an AI agent for Vorce-Studios with roleKey=%1. Your instructions are at %2. Your policies are at %3. Read both files carefully and follow them."
