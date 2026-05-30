from PIL import Image

def create_composed_icon():
    # Define paths
    foreground_path = 'assets/icon/mosque_white_512.png'
    output_path = 'assets/icon/icon_composed.png'
    
    # Define colors
    bg_color = (76, 175, 80) # #4CAF50 Green
    
    try:
        # Open foreground image
        foreground = Image.open(foreground_path).convert("RGBA")
        
        # Create background image
        background = Image.new('RGBA', foreground.size, bg_color)
        
        # Paste foreground onto background
        # Use foreground as mask for transparency
        background.paste(foreground, (0, 0), foreground)
        
        # Save composed image
        background.save(output_path)
        print(f"Successfully created composed icon at {output_path}")
        
    except Exception as e:
        print(f"Error creating composed icon: {e}")

if __name__ == "__main__":
    create_composed_icon()
