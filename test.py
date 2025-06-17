import random

def generate_batch(n=100):
    return [random.randint(0, 1) for _ in range(n)]

def main():
    batch = generate_batch(100)
    print(batch)

if __name__ == "__main__":
    main()
