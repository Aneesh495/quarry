#!/usr/bin/env python3
"""
setup.py
Build and packaging script for PyQuarry Python SDK.
"""

from setuptools import setup, find_packages

setup(
    name="pyquarry",
    version="1.0.0",
    description="Python client bindings and DataFrame bridge for Quarry analytical database",
    author="Aneesh Krishna",
    packages=find_packages(),
    python_requires=">=3.8",
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: Science/Research",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Database :: Database Engines/Servers",
    ],
    extras_require={
        "pandas": ["pandas>=1.3.0"],
        "polars": ["polars>=0.18.0"],
        "arrow": ["pyarrow>=8.0.0"],
        "all": ["pandas>=1.3.0", "polars>=0.18.0", "pyarrow>=8.0.0"],
    },
)
