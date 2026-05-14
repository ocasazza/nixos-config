#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p "python3.withPackages (ps: with ps; [ pillow cairosvg ])"

import argparse
import sys
import shutil
from io import BytesIO
from PIL import Image

try:
    import cairosvg
except ImportError:
    print("Error: 'cairosvg' is required. If not using nix-shell, install with 'pip install cairosvg'.")
    sys.exit(1)

def convert_svg_to_pixel_text(input_path, output_path, width=None, height=None, char="▓", ratio=0.5):
    """
    Converts an SVG file to a text file with pixel colors formatted as [#RRGGBB]▓[/].
    
    ratio: vertical scaling factor to compensate for terminal character aspect ratio.
           Default 0.5 assumes characters are twice as tall as they are wide.
    """
    print(f"Reading {input_path}...")
    
    try:
        # Get terminal width if not specified
        term_width, _ = shutil.get_terminal_size()
        if width is None:
            width = min(term_width, 100) # Default to max 100 or term width
            print(f"No width specified. Using {width} (Terminal width: {term_width})")

        # First rasterize at a reasonably high resolution to get aspect ratio if needed
        # Or just use cairosvg to get the dimensions.
        # cairosvg.svg2png doesn't easily return dimensions without rasterizing.
        # We'll rasterize once at target width.
        
        png_data = cairosvg.svg2png(url=input_path, output_width=width)
        img = Image.open(BytesIO(png_data)).convert('RGBA') # Use RGBA to handle transparency
        orig_w, orig_h = img.size
        
        # Calculate target height based on aspect ratio and terminal character ratio
        if height is None:
            height = int(orig_h * (width / orig_w) * ratio)
            if height < 1: height = 1
        
        print(f"Rasterizing to {width}x{height}...")
        # Re-rasterize at final dimensions for better quality than Pillow resizing
        png_data = cairosvg.svg2png(url=input_path, output_width=width, output_height=height)
        img = Image.open(BytesIO(png_data)).convert('RGBA')
        
        w, h = img.size
        pixels = img.load()
        
        output_str = []
        for y in range(h):
            line_parts = []
            for x in range(w):
                r, g, b, a = pixels[x, y]
                
                # If transparent, we might want a default background or just skip
                # For skins, we usually want the background color. 
                # Here we'll just alpha blend with black if semi-transparent
                if a < 128:
                    # Treat as empty space or background? 
                    # The user's format doesn't have a 'none' color.
                    # We'll just use a space if fully transparent, but the prompt says ▓.
                    # Let's just use the color even if transparent, or black.
                    line_parts.append(" ") 
                    continue
                
                hex_color = f"#{r:02x}{g:02x}{b:02x}".upper()
                line_parts.append(f"[{hex_color}]{char}[/]")
            
            output_str.append("".join(line_parts))
        
        final_text = "\n".join(output_str)
        
        if output_path == "-":
            print("\n--- BEGIN OUTPUT ---")
            print(final_text)
            print("--- END OUTPUT ---")
        else:
            with open(output_path, 'w', encoding='utf-8') as f:
                f.write(final_text + "\n")
            print(f"Successfully wrote output to {output_path}")
        
    except Exception as e:
        print(f"Error during conversion: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Convert SVG to color-tagged text pixels for Hermes skins.")
    parser.add_argument("input", help="Path to the input SVG file")
    parser.add_argument("output", help="Path to the output text file (use '-' for stdout)")
    parser.add_argument("--width", type=int, help="Target width in characters (defaults to terminal width or 100)")
    parser.add_argument("--height", type=int, help="Target height in characters (defaults to auto-calculated)")
    parser.add_argument("--char", default="▓", help="Character to use for pixels (default: ▓)")
    parser.add_argument("--ratio", type=float, default=0.5, help="Vertical scale ratio (default 0.5 for terminal fonts)")

    args = parser.parse_args()
    
    convert_svg_to_pixel_text(args.input, args.output, args.width, args.height, args.char, args.ratio)

if __name__ == "__main__":
    main()
