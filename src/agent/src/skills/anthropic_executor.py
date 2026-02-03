#!/usr/bin/env python3
"""
Anthropic Computer Use Skills Executor
Executes bash and text_editor skills via subprocess

FREE - No API costs, runs locally
Based on: https://github.com/anthropics/anthropic-quickstarts/tree/main/computer-use-demo
"""
import sys
import json
import argparse
import subprocess
import os
from pathlib import Path
from typing import Dict, Any

def execute_bash(params: Dict[str, Any]) -> Dict[str, Any]:
    """
    Execute bash command in sandboxed environment
    
    Args:
        params: {
            "command": str,
            "timeout": int (default 30),
            "workdir": str (default "/tmp")
        }
    
    Returns:
        {
            "stdout": str,
            "stderr": str,
            "exit_code": int,
            "command": str
        }
    """
    command = params.get("command", "")
    timeout = params.get("timeout", 30)
    workdir = params.get("workdir", "/tmp")
    
    if not command:
        raise ValueError("Command is required")
    
    # Security: Block dangerous commands
    dangerous_patterns = [
        "rm -rf /",
        "mkfs",
        "dd if=/dev",
        ":(){:|:&};:",  # Fork bomb
        "chmod 777",
        "chmod -R 777",
    ]
    
    for pattern in dangerous_patterns:
        if pattern in command:
            raise ValueError(f"Dangerous command blocked: {pattern}")
    
    # Execute in safe working directory
    try:
        result = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=workdir,
        )
        
        return {
            "stdout": result.stdout,
            "stderr": result.stderr,
            "exit_code": result.returncode,
            "command": command,
        }
    except subprocess.TimeoutExpired:
        raise TimeoutError(f"Command timeout after {timeout} seconds")
    except Exception as e:
        raise RuntimeError(f"Command execution failed: {str(e)}")


def execute_text_editor(params: Dict[str, Any]) -> Dict[str, Any]:
    """
    Perform file editing operations
    
    Args:
        params: {
            "command": "create" | "view" | "insert" | "replace" | "delete",
            "path": str,
            "content": str (for create/insert/replace),
            "line_number": int (for insert/replace/delete)
        }
    
    Returns:
        {
            "status": str,
            "path": str,
            "content": str (for view),
            "lines_affected": int
        }
    """
    command = params.get("command")
    path = params.get("path")
    content = params.get("content", "")
    line_number = params.get("line_number")
    
    if not command or not path:
        raise ValueError("command and path are required")
    
    # Security: Restrict to /tmp directory
    path_obj = Path(path).resolve()
    if not str(path_obj).startswith("/tmp"):
        raise ValueError("File operations restricted to /tmp directory")
    
    if command == "create":
        path_obj.parent.mkdir(parents=True, exist_ok=True)
        path_obj.write_text(content)
        return {
            "status": "created",
            "path": str(path_obj),
            "lines_affected": content.count("\n") + 1,
        }
    
    elif command == "view":
        if not path_obj.exists():
            raise FileNotFoundError(f"File not found: {path}")
        content = path_obj.read_text()
        return {
            "status": "viewed",
            "path": str(path_obj),
            "content": content,
            "lines_affected": content.count("\n") + 1,
        }
    
    elif command == "insert":
        if line_number is None:
            raise ValueError("line_number is required for insert")
        
        if not path_obj.exists():
            raise FileNotFoundError(f"File not found: {path}")
        
        lines = path_obj.read_text().splitlines(keepends=True)
        lines.insert(line_number - 1, content + "\n")
        path_obj.write_text("".join(lines))
        
        return {
            "status": "inserted",
            "path": str(path_obj),
            "lines_affected": 1,
        }
    
    elif command == "replace":
        if line_number is None:
            raise ValueError("line_number is required for replace")
        
        if not path_obj.exists():
            raise FileNotFoundError(f"File not found: {path}")
        
        lines = path_obj.read_text().splitlines(keepends=True)
        if line_number < 1 or line_number > len(lines):
            raise ValueError(f"Invalid line number: {line_number}")
        
        lines[line_number - 1] = content + "\n"
        path_obj.write_text("".join(lines))
        
        return {
            "status": "replaced",
            "path": str(path_obj),
            "lines_affected": 1,
        }
    
    elif command == "delete":
        if line_number is None:
            # Delete entire file
            path_obj.unlink()
            return {
                "status": "deleted",
                "path": str(path_obj),
                "lines_affected": 0,
            }
        else:
            # Delete specific line
            if not path_obj.exists():
                raise FileNotFoundError(f"File not found: {path}")
            
            lines = path_obj.read_text().splitlines(keepends=True)
            if line_number < 1 or line_number > len(lines):
                raise ValueError(f"Invalid line number: {line_number}")
            
            del lines[line_number - 1]
            path_obj.write_text("".join(lines))
            
            return {
                "status": "deleted_line",
                "path": str(path_obj),
                "lines_affected": 1,
            }
    
    else:
        raise ValueError(f"Unknown command: {command}")


def main():
    parser = argparse.ArgumentParser(description="Execute Anthropic Computer Use skills")
    parser.add_argument("--skill", required=True, help="Skill name (bash, text_editor)")
    parser.add_argument("--params", required=True, help="JSON parameters")
    
    args = parser.parse_args()
    
    try:
        params = json.loads(args.params)
    except json.JSONDecodeError as e:
        print(json.dumps({"error": f"Invalid JSON parameters: {str(e)}"}))
        sys.exit(1)
    
    try:
        if args.skill == "bash":
            result = execute_bash(params)
        elif args.skill == "text_editor":
            result = execute_text_editor(params)
        else:
            result = {"error": f"Unknown skill: {args.skill}"}
            sys.exit(1)
        
        # Output result as JSON
        print(json.dumps(result))
        sys.exit(0)
    
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)


if __name__ == "__main__":
    main()
