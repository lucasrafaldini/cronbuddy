import logging
import sys


def setup_logger(name: str = "cronbuddy") -> logging.Logger:
    """Sets up a structured logger for the application.

    Args:
        name: The name of the logger.

    Returns:
        A configured logging.Logger instance.
    """
    logger = logging.getLogger(name)
    
    if not logger.handlers:
        logger.setLevel(logging.INFO)
        
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        
        # Console handler
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setFormatter(formatter)
        logger.addHandler(console_handler)
        
    return logger

logger = setup_logger()
